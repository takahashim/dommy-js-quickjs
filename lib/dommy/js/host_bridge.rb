# frozen_string_literal: true

require "json"

module Dommy
  module Js
    # Engine-agnostic core of the JS<->Ruby DOM bridge. Given a `backend` that
    # can evaluate JS, register Ruby host functions, and call back into JS,
    # HostBridge exposes a Ruby object to the JS side as an ES Proxy whose
    # property/method access routes into the bridge ABI:
    #   __js_get__(name) / __js_set__(name, value) / __js_call__(method, args)
    #
    # Nothing here is QuickJS-specific; this layer is intended to move into a
    # future `dommy-js` gem with QuickJS/wasm backends plugged in underneath.
    #
    # Two collaborators keep the marshalling core free of DOM specifics:
    #   DomInterfaces       — interface name/chain derivation (instanceof support)
    #   ConstructorRegistry — `new Event(...)` style reverse construction
    #
    # Backend contract:
    #   backend.eval(js)                         -> evaluate top-level JS
    #   backend.define_host_function(name) { }   -> expose a Ruby block as a JS global
    #   backend.call_js(path, *args)             -> invoke a JS global function by path
    #
    # The host object must implement __js_get__/__js_set__/__js_call__, and the
    # bridge needs to know which names are methods (callable via __js_call__)
    # vs. properties (read via __js_get__) — see #method_names.
    class HostBridge
      # JS half of the bridge (globalThis.__rbHost). Read from a companion file
      # so it stays lintable/highlightable rather than buried in a heredoc.
      # ::File — inside module Dommy, bare `File` resolves to Dommy::File (the
      # File API class), not Ruby's file class.
      HOST_RUNTIME_JS = ::File.read(::File.join(__dir__, "host_runtime.js")).freeze
      # The WICG Observable polyfill (Observable/Subscriber + EventTarget.when),
      # evaluated after the DOM interface prototypes are seeded.
      OBSERVABLE_RUNTIME_JS = ::File.read(::File.join(__dir__, "observable_runtime.js")).freeze

      def initialize(backend)
        @backend = backend
        @handles = HandleTable.new
        @callback_objects = {}
        @constructors = ConstructorRegistry.new
        @custom_elements = CustomElements.new(self)
        @microtask_procs = {}
        @microtask_seq = 0
        install!
      end

      # Bind a Ruby object to a JS global of the given name.
      def define_host_object(name, obj)
        handle = @handles.register(obj)
        @backend.eval("globalThis[#{name.to_s.to_json}] = __rbHost.makeProxy(#{handle}); undefined;")
        obj
      end

      # Bind the window the bridge draws on for JS constructors (new Event(...))
      # and custom element registration. Called by Runtime#install_window — kept
      # distinct from define_host_object so the generic binder has no hidden
      # side effects.
      def window=(win)
        @constructors.source = win
        @custom_elements.window = win
        # Now that constructors are resolvable, expose their static methods
        # (URL.createObjectURL, …) on the seeded interface globals, and expose
        # the constructors themselves on the window proxy (window.Node,
        # document.defaultView.DOMException, …).
        @backend.call_js("__rbHost.attachStatics")
        @backend.call_js("__rbHost.exposeConstructorsOnWindow")
        # Route Dommy's host-side microtasks (MutationObserver delivery, …) onto
        # the engine's native promise-job queue, so they interleave FIFO with JS
        # `await`/Promise reactions instead of draining on a separate pass (which
        # would deliver e.g. MutationObserver records only after `await
        # Promise.resolve()`, batching several mutations into one callback).
        if win.respond_to?(:scheduler) && win.scheduler.respond_to?(:native_microtask_scheduler=)
          win.scheduler.native_microtask_scheduler = ->(callback) { schedule_native_microtask(callback) }
        end
      end

      # Enqueue a Ruby callback as a NATIVE microtask (a resolved-promise job), so
      # it runs in FIFO order with the engine's other promise jobs.
      def schedule_native_microtask(callback)
        id = (@microtask_seq += 1)
        @microtask_procs[id] = callback
        @backend.call_js("__rbHost.scheduleMicrotask", id)
        nil
      end

      # Expose the seeded interface constructors (Element, Node, DOMException, …)
      # on a secondary window object — an iframe's contentWindow — so cross-window
      # `instanceof subWin.Element` and `subDoc.defaultView.DOMException` resolve
      # to the same constructors the top window uses. Idempotent per window.
      def expose_constructors_on(window_obj)
        handle = @handles.register(window_obj)
        # Retain the proxy in a JS-side registry: the constructors are defined as
        # own properties on the proxy's target, so the proxy must stay alive (and
        # keep its handle) — otherwise GC releases it and a later
        # `iframe.contentWindow` rebuilds a fresh, constructor-less proxy.
        @backend.eval(<<~JS)
          (globalThis.__rbSubWindows ||= []).push(__rbHost.makeProxy(#{handle}));
          __rbHost.exposeConstructorsOnWindow(globalThis.__rbSubWindows.at(-1));
        JS
        window_obj
      end

      # Invoke a JS custom element lifecycle callback (connectedCallback etc.) for
      # a Dommy node. Called by the bridged custom element class (see CustomElements).
      def invoke_lifecycle(node, callback, args)
        handle = @handles.register(node)
        unwrap(@backend.call_js("__rbHost.invokeLifecycle", handle, callback, wrap(Array(args))))
      end

      # Invoke a retained live JS function by id (used by HostCallback). The JS
      # side returns a `dehydrate`d (tagged) value, so unwrap it back to Ruby:
      # a callback that returns e.g. a Promise proxy must come back as the live
      # PromiseValue, otherwise Dommy can't adopt it (breaking
      # `fetch().then(r => r.json()).then(…)` chains).
      def invoke_callback(id, args, this_arg = nil)
        unwrap(@backend.call_js("__rbHost.invokeCallback", id, wrap(Array(args)), wrap(this_arg)))
      end

      # Turn a JS-side tagged value (produced by __rbHost.tag) back into Ruby:
      # tagged handles become the original Ruby DOM objects. Used for return
      # values that may contain DOM nodes (e.g. evaluate_script).
      def decode(tagged)
        unwrap(tagged)
      end

      # Number of live handle entries. Introspection for lifetime tests.
      def registered_count
        @handles.size
      end

      private

      def install!
        @backend.define_host_function("__rb_host_get") do |handle, prop|
          dom_guard do
            obj = host(handle)
            wrap(obj.respond_to?(:__js_get__) ? obj.__js_get__(prop) : nil)
          end
        end
        @backend.define_host_function("__rb_host_set") do |handle, prop, value|
          # Returns whether Dommy handled the write as a DOM property. When it
          # didn't (or the object has no __js_set__), the JS side keeps the value
          # as an expando (preserving object/instance field identity). Wrapped in
          # dom_guard so a throwing setter (e.g. `documentElement.outerHTML = …` →
          # NoModificationAllowedError) crosses as a tagged exception the JS set
          # trap re-throws, rather than escaping as a raw Ruby error.
          dom_guard do
            obj = host(handle)
            obj.respond_to?(:__js_set__) ? dommy_handled?(obj.__js_set__(prop, unwrap(value))) : false
          end
        end
        @backend.define_host_function("__rb_host_call") do |handle, method, args|
          dom_guard do
            obj = host(handle)
            obj.respond_to?(:__js_call__) ? wrap(obj.__js_call__(method, unwrap(args))) : nil
          end
        end
        # 2d: one call returns everything makeProxy needs — interface name +
        # chain, method names, and the custom element tag (if any).
        @backend.define_host_function("__rb_host_describe") do |handle|
          obj = host(handle)
          info = DomInterfaces.info(obj)
          info["methods"] = method_names(obj)
          # Mark JS-defined custom elements so makeProxy upgrades them on crossing.
          info["ce"] = obj.__js_custom_element_name__ if obj.respond_to?(:__js_custom_element_name__)
          info
        end
        @backend.define_host_function("__rb_release_handle") do |handle|
          @handles.release(handle)
          nil
        end
        # Run a Ruby microtask previously registered by schedule_native_microtask,
        # invoked from the resolved-promise job scheduleMicrotask queued.
        @backend.define_host_function("__rb_run_microtask") do |id|
          callback = @microtask_procs.delete(id)
          callback&.call
          nil
        end
        # WebIDL "supported property names" for a legacy platform object (a live
        # array-like/maplike collection): the current ordered named-property
        # keys. Queried per ownKeys / getOwnPropertyDescriptor so it tracks DOM
        # mutations. Nil when the object has no named getter.
        @backend.define_host_function("__rb_named_props") do |handle|
          obj = host(handle)
          obj.respond_to?(:__js_named_props__) ? Array(obj.__js_named_props__).map(&:to_s) : nil
        end
        # Named deleter (`delete el.dataset.foo`): true when the object handled
        # the delete, false/UNHANDLED when the JS side should fall back to its
        # own (expando) delete.
        @backend.define_host_function("__rb_host_delete") do |handle, prop|
          dom_guard do
            obj = host(handle)
            obj.respond_to?(:__js_delete__) ? dommy_handled?(obj.__js_delete__(prop)) : false
          end
        end
        # `new Event(...)` / `new DOMException(...)` from a bare interface
        # constructor — resolve the named constructor and build. Returns nil when
        # the interface isn't constructable, so the JS side throws.
        @backend.define_host_function("__rb_construct") do |name, args|
          dom_guard do
            ctor = @constructors.resolve(name)
            ctor ? wrap(ctor.__js_new__(unwrap(args))) : nil
          end
        end
        # Static/class methods on an interface constructor (URL.createObjectURL,
        # URL.parse, …): names to expose, and the dispatch.
        @backend.define_host_function("__rb_static_names") do |name|
          ctor = @constructors.resolve(name)
          ctor.respond_to?(:__js_class_method_names__) ? ctor.__js_class_method_names__ : []
        end
        @backend.define_host_function("__rb_static_call") do |name, method, args|
          dom_guard do
            ctor = @constructors.resolve(name)
            ctor.respond_to?(:__js_call__) ? wrap(ctor.__js_call__(method, unwrap(args))) : nil
          end
        end
        # 1d: customElements.define(name, JSClass) wires a Dommy custom element.
        @backend.define_host_function("__rb_define_custom_element") do |name, observed|
          @custom_elements.define(name, Array(observed))
          nil
        end
        # 1d: customElements.upgrade(root) — delegate to Dommy's registry.
        @backend.define_host_function("__rb_upgrade_custom_elements") do |handle|
          @custom_elements.upgrade(host(handle))
          nil
        end
        @backend.eval(HOST_RUNTIME_JS)
        # Seed base interface prototypes from the single Ruby-side hierarchy.
        @backend.eval("__rbHost.seedInterfaces(#{JSON.generate(DomInterfaces::BASE_CHAINS)});")
        # Observable depends on EventTarget.prototype existing (seeded above).
        @backend.eval(OBSERVABLE_RUNTIME_JS)
      end

      def host(handle)
        @handles.fetch(handle)
      end

      # Run a host-function body, converting a raised Dommy::DOMException into a
      # tagged marker that the JS side (rehydrate) re-throws as a real
      # DOMException (name + legacy code, `instanceof DOMException`). Otherwise
      # the quickjs gem flattens it to a plain Error — no name/code — which
      # breaks `assert_throws_dom` and every DOM error contract (removeChild
      # NotFoundError, classList SyntaxError/InvalidCharacterError, …).
      def dom_guard
        yield
      rescue Dommy::Bridge::ThrowValue => e
        # A host method threw an arbitrary value (e.g. throwIfAborted's reason);
        # re-throw it verbatim JS-side, identity preserved.
        {"__rb_throw__" => wrap(e.value)}
      rescue Dommy::DOMException => e
        {"__rb_exception__" => {"name" => e.name, "message" => e.message, "code" => e.code}}
      rescue Dommy::Bridge::TypeError => e
        # A deliberate, spec-mandated JS TypeError (e.g. `new URL(bad)`). Tagged
        # so rehydrate rethrows a real `TypeError` — `assert_throws_js(TypeError,
        # …)` checks `instanceof TypeError`, which a DOMException/Error fails.
        {"__rb_exception__" => {"name" => "TypeError", "message" => e.message, "js_native" => true}}
      rescue Dommy::Bridge::RangeError => e
        # A spec-mandated JS RangeError (e.g. `new Response(b, {status: 42})`).
        {"__rb_exception__" => {"name" => "RangeError", "message" => e.message, "js_native" => true}}
      end

      # Ruby -> JS: tag bridge-able objects so the JS side can proxy them.
      # Recurses Array and Hash so nested DOM nodes are tagged too (symmetric
      # with #unwrap).
      def wrap(value)
        # A `__js_call__` may return the UNDEFINED sentinel for a void op; marshal
        # it so the JS side yields `undefined` rather than `null`.
        if defined?(Dommy::Bridge::UNDEFINED) && value.equal?(Dommy::Bridge::UNDEFINED)
          return {"__rb_undefined" => true}
        end
        # A byte buffer tagged ArrayBuffer crosses back as a bare ArrayBuffer
        # (checked before Bytes, since ArrayBuffer < Bytes).
        if defined?(Dommy::Bridge::ArrayBuffer) && value.is_a?(Dommy::Bridge::ArrayBuffer)
          return {"__rb_arraybuffer" => value.to_a}
        end
        # A byte buffer crosses back as a JS Uint8Array.
        if defined?(Dommy::Bridge::Bytes) && value.is_a?(Dommy::Bridge::Bytes)
          return {"__rb_bytes" => value.to_a}
        end
        # An opaque JS value returns as its original JS object (identity kept).
        if defined?(Dommy::Bridge::JSValue) && value.is_a?(Dommy::Bridge::JSValue)
          return {"__rb_js_ref" => value.ref}
        end

        case value
        when Array
          value.map { |element| wrap(element) }
        when Hash
          value.transform_values { |element| wrap(element) }
        when HostCallback
          # A JS function that crossed into Ruby returns as the same live JS
          # function (not a proxy), so callbacks nested in objects round-trip.
          {"__rb_callback" => value.id}
        else
          if bridgeable?(value)
            {"__rb_handle" => @handles.register(value)}
          else
            value
          end
        end
      end

      # A value crosses as a proxy if it implements any of the bridge ABI — not
      # only __js_get__: method-only objects (observers) and constructors expose
      # __js_call__ / __js_new__ without properties.
      def bridgeable?(value)
        value.respond_to?(:__js_get__) ||
          value.respond_to?(:__js_call__) ||
          value.respond_to?(:__js_new__)
      end

      # JS -> Ruby: rebuild tagged handles / callbacks into Ruby objects.
      def unwrap(value)
        case value
        when Array
          value.map { |element| unwrap(element) }
        when Hash
          if value.key?("__rb_handle")
            host(value["__rb_handle"])
          elsif value.key?("__rb_callback")
            id = value["__rb_callback"]
            @callback_objects[id] ||= HostCallback.new(self, id)
          elsif value.key?("__rb_js_ref")
            # An opaque JS value (a non-plain object Ruby just stores and returns,
            # e.g. an abort reason) — kept as a handle so it round-trips with
            # identity rather than being flattened to a Hash.
            if defined?(Dommy::Bridge::JSValue)
              Dommy::Bridge::JSValue.new(value["__rb_js_ref"], value["__rb_js_label"])
            else
              value
            end
          elsif value.key?("__rb_undefined")
            # A top-level JS `undefined` argument — distinct from JS null (nil).
            defined?(Dommy::Bridge::UNDEFINED) ? Dommy::Bridge::UNDEFINED : nil
          elsif value.key?("__rb_bytes")
            # A JS ArrayBuffer / TypedArray argument arrives as a byte buffer.
            defined?(Dommy::Bridge::Bytes) ? Dommy::Bridge::Bytes.new(value["__rb_bytes"]) : value["__rb_bytes"]
          else
            value.transform_values { |element| unwrap(element) }
          end
        when :undefined
          # A raw JS `undefined` (e.g. a property-set value, which crosses via
          # `dehydrate` rather than the tagged `dehydrateArgs`) reaches Ruby as
          # the gem's `:undefined` symbol. Normalize it to the same sentinel a
          # tagged top-level undefined produces, so setters can distinguish it
          # from `null` (e.g. `el.ariaLabel = undefined` removes the attribute).
          defined?(Dommy::Bridge::UNDEFINED) ? Dommy::Bridge::UNDEFINED : nil
        else
          value
        end
      end

      # Which property names should be treated as callable methods. The ABI
      # keeps properties (__js_get__) and methods (__js_call__) in disjoint
      # namespaces, so the proxy asks the object to self-describe via the bridge
      # ABI method __js_method_names__. method_defined? (not respond_to?) avoids
      # classes whose respond_to_missing? answers true for arbitrary names (e.g.
      # StyleDeclaration's CSS-property accessors).
      def method_names(obj)
        return [] unless obj.class.method_defined?(:__js_method_names__)

        Array(obj.__js_method_names__).map(&:to_s)
      end

      # Did Dommy treat a __js_set__ as a real DOM property? A returned UNHANDLED
      # sentinel means "no" (the JS side then keeps it as an expando). Tolerant of
      # older Dommy without the sentinel (treats everything as handled).
      def dommy_handled?(result)
        !(defined?(Dommy::Bridge::UNHANDLED) && result == Dommy::Bridge::UNHANDLED)
      end
    end

    # An event listener backed by a live JS function. Implements only the bridge
    # ABI (__js_call__) — not #call/#handle_event — so Dommy's invoke_listener
    # routes through the __js_call__("call", [event]) branch.
    class HostCallback
      attr_reader :id

      def initialize(bridge, id)
        @bridge = bridge
        @id = id
      end

      def __js_call__(method, args)
        return nil unless method == "call"

        @bridge.invoke_callback(@id, args)
      end

      # Invoke with an explicit `this` receiver — e.g. a MutationObserver
      # callback whose `this` must be the observer, or an event listener whose
      # `this` is the currentTarget.
      def __js_call_with_this__(args, this_arg)
        @bridge.invoke_callback(@id, args, this_arg)
      end
    end
  end
end
