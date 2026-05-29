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
    # Backend contract:
    #   backend.eval(js)                         -> evaluate top-level JS
    #   backend.define_host_function(name) { }   -> expose a Ruby block as a JS global
    #   backend.call_js(path, *args)             -> invoke a JS global function by path
    #
    # The host object must implement __js_get__/__js_set__/__js_call__, and the
    # bridge needs to know which names are methods (callable via __js_call__)
    # vs. properties (read via __js_get__) — see #method_names.
    class HostBridge
      # Built once per backend. Defines globalThis.__rbHost.{makeProxy,invokeCallback}.
      # Values crossing the boundary are tagged: a bridge-able Ruby object is
      # `{ __rb_handle: id }`, a JS function passed to Ruby is `{ __rb_callback: id }`.
      HOST_RUNTIME_JS = <<~'JS'
        globalThis.__rbHost = (function () {
          const HKEY = Symbol("rbHandle");
          const cache = new Map();            // handle -> WeakRef(proxy)
          const callbacks = new Map();
          const callbackIds = new WeakMap();
          let nextCb = 1;

          // When a proxy is garbage-collected, drop the Ruby-side handle entry
          // (unless a live re-proxy for the same handle exists). Keeps the
          // registry bounded on long-lived VMs. Handles are monotonic on the
          // Ruby side, so a handle never refers to two different objects.
          const finalizers = new FinalizationRegistry((handle) => {
            const ref = cache.get(handle);
            if (!ref || ref.deref() === undefined) {
              cache.delete(handle);
              __rb_release_handle(handle);
            }
          });

          function isProxy(v) {
            return v !== null && typeof v === "object" && v[HKEY] !== undefined;
          }

          // Same function -> same id, so addEventListener / removeEventListener
          // round-trip to the same Ruby HostCallback (Dommy matches by identity).
          function registerCallback(fn) {
            if (callbackIds.has(fn)) return callbackIds.get(fn);
            const id = nextCb++;
            callbacks.set(id, fn);
            callbackIds.set(fn, id);
            return id;
          }

          // Called from Ruby when a host event dispatch reaches a JS-registered
          // listener. The live function (closure intact) is invoked; tagged args
          // (e.g. an Event handle) are rehydrated to proxies first.
          function invokeCallback(id, args) {
            const fn = callbacks.get(id);
            if (!fn) return undefined;
            return dehydrate(fn.apply(undefined, rehydrate(args || [])));
          }

          function dehydrate(v, seen) {
            if (typeof v === "function") return { __rb_callback: registerCallback(v) };
            if (isProxy(v)) return { __rb_handle: v[HKEY] };
            if (v !== null && typeof v === "object") {
              seen = seen || new WeakSet();
              if (seen.has(v)) return undefined; // break reference cycles
              seen.add(v);
              if (Array.isArray(v)) return v.map((e) => dehydrate(e, seen));
              const out = {};
              for (const k of Object.keys(v)) out[k] = dehydrate(v[k], seen);
              return out;
            }
            return v;
          }

          function rehydrate(v) {
            if (Array.isArray(v)) return v.map(rehydrate);
            if (v !== null && typeof v === "object") {
              if ("__rb_handle" in v) return makeProxy(v.__rb_handle);
              const out = {};
              for (const k of Object.keys(v)) out[k] = rehydrate(v[k]);
              return out;
            }
            return v;
          }

          function makeProxy(handle) {
            const ref = cache.get(handle);
            if (ref) {
              const existing = ref.deref();
              if (existing) return existing;
            }
            const methods = new Set(__rb_host_methods(handle));
            const p = new Proxy({}, {
              get(_t, prop) {
                if (prop === HKEY) return handle;
                if (typeof prop === "symbol") return undefined;
                if (methods.has(prop)) {
                  return function (...args) {
                    return rehydrate(__rb_host_call(handle, prop, dehydrate(args)));
                  };
                }
                return rehydrate(__rb_host_get(handle, prop));
              },
              set(_t, prop, value) {
                if (typeof prop !== "symbol") {
                  __rb_host_set(handle, prop, dehydrate(value));
                }
                return true;
              },
              has() { return true; }
            });
            cache.set(handle, new WeakRef(p));
            finalizers.register(p, handle);
            return p;
          }

          return { makeProxy, invokeCallback, tag: dehydrate };
        })();
      JS

      def initialize(backend)
        @backend = backend
        @handles = HandleTable.new
        @callback_objects = {}
        install!
      end

      # Bind a Ruby object to a JS global of the given name.
      def define_host_object(name, obj)
        handle = @handles.register(obj)
        @backend.eval("globalThis[#{name.to_s.to_json}] = __rbHost.makeProxy(#{handle}); undefined;")
        obj
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
        @backend.define_host_function("__rb_release_handle") do |handle|
          @handles.release(handle)
          nil
        end
        @backend.eval(HOST_RUNTIME_JS)
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
