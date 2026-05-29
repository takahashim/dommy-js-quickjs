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
        install!
      end

      # Bind a Ruby object to a JS global of the given name.
      def define_host_object(name, obj)
        handle = @handles.register(obj)
        @backend.eval("globalThis[#{name.to_s.to_json}] = __rbHost.makeProxy(#{handle}); undefined;")
        obj
      end

      # Set the window that supplies JS constructors (new Event(...) etc.). Called
      # by Runtime#install_window — kept distinct from define_host_object so the
      # generic binder has no hidden side effects.
      def constructor_source=(win)
        @constructors.source = win
      end

      # Invoke a retained live JS function by id (used by HostCallback).
      def invoke_callback(id, args)
        @backend.call_js("__rbHost.invokeCallback", id, wrap(Array(args)))
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
          wrap(host(handle).__js_get__(prop))
        end
        @backend.define_host_function("__rb_host_set") do |handle, prop, value|
          host(handle).__js_set__(prop, unwrap(value))
          nil
        end
        @backend.define_host_function("__rb_host_call") do |handle, method, args|
          wrap(host(handle).__js_call__(method, unwrap(args)))
        end
        @backend.define_host_function("__rb_host_methods") do |handle|
          method_names(host(handle))
        end
        @backend.define_host_function("__rb_host_interface") do |handle|
          DomInterfaces.info(host(handle))
        end
        @backend.define_host_function("__rb_release_handle") do |handle|
          @handles.release(handle)
          nil
        end
        # `new Event(...)` / `new DOMException(...)` from a bare interface
        # constructor — resolve the named constructor and build. Returns nil when
        # the interface isn't constructable, so the JS side throws.
        @backend.define_host_function("__rb_construct") do |name, args|
          ctor = @constructors.resolve(name)
          ctor ? wrap(ctor.__js_new__(unwrap(args))) : nil
        end
        @backend.eval(HOST_RUNTIME_JS)
        # Seed base interface prototypes from the single Ruby-side hierarchy.
        @backend.eval("__rbHost.seedInterfaces(#{JSON.generate(DomInterfaces::BASE_CHAINS)});")
      end

      def host(handle)
        @handles.fetch(handle)
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
        else
          if value.respond_to?(:__js_get__)
            {"__rb_handle" => @handles.register(value)}
          else
            value
          end
        end
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
    end

    # An event listener backed by a live JS function. Implements only the bridge
    # ABI (__js_call__) — not #call/#handle_event — so Dommy's invoke_listener
    # routes through the __js_call__("call", [event]) branch.
    class HostCallback
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
