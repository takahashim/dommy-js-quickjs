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

      def initialize(backend)
        @backend = backend
        @handles = HandleTable.new
        @callback_objects = {}
        @constructors = ConstructorRegistry.new
        @custom_elements = CustomElements.new(self)
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
        # (URL.createObjectURL, …) on the seeded interface globals.
        @backend.call_js("__rbHost.attachStatics")
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
      def invoke_callback(id, args)
        unwrap(@backend.call_js("__rbHost.invokeCallback", id, wrap(Array(args))))
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
          # as an expando (preserving object/instance field identity).
          obj = host(handle)
          obj.respond_to?(:__js_set__) ? dommy_handled?(obj.__js_set__(prop, unwrap(value))) : false
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
      rescue Dommy::DOMException => e
        {"__rb_exception__" => {"name" => e.name, "message" => e.message, "code" => e.code}}
      end

      # Ruby -> JS: tag bridge-able objects so the JS side can proxy them.
      # Recurses Array and Hash so nested DOM nodes are tagged too (symmetric
      # with #unwrap).
      def wrap(value)
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
          else
            value.transform_values { |element| unwrap(element) }
          end
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
    end
  end
end
