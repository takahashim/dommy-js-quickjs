# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # Handle-oriented JS access for a wasm guest (e.g. mruby-in-wasm under
      # wasmtime-rb). Distinct from the Proxy-based HostBridge: instead of
      # exposing Ruby DOM objects to JS as proxies, this lets a guest treat any
      # JS value as an opaque integer ref it can get/set/call/new on — the shape
      # the guest's `js_*` bridge imports need.
      #
      # The JS half lives in host_runtime.js (the `wasm*` functions on
      # `__rbHost`); this is the thin Ruby facade over them. Every non-primitive
      # JS value crosses as a `JSValue` (an opaque ref into the VM); primitives
      # cross as plain Ruby values. Callbacks the guest registers become JS
      # functions (also refs) that route back through `__rbWasmInvoke`.
      class WasmBridge
        # An opaque handle to a JS value living in the VM. `ref` is the integer
        # id into the JS-side jsRefs table.
        JSValue = Struct.new(:ref) do
          def to_s
            "#<JSValue ref=#{ref}>"
          end
        end

        def initialize(backend)
          @backend = backend
        end

        # Install the dispatcher JS callbacks route back through. The block
        # receives (invoke_id, packed_args) and must return a packed result
        # (the same tagged shape #pack produces). Called once by the embedder.
        def on_invoke(&block)
          @backend.define_host_function("__rbWasmInvoke") do |invoke_id, args|
            block.call(invoke_id.to_i, args)
          end
          self
        end

        # A ref to the VM's globalThis — the guest's `js_global`.
        def global_ref
          unpack(@backend.call_js("__rbHost.wasmGlobalRef"))
        end

        # Evaluate real JS source in global scope; returns the (packed) result.
        def eval_js(src)
          unpack(@backend.call_js("__rbHost.wasmEval", src.to_s))
        end

        def get(recv, prop)
          unpack(@backend.call_js("__rbHost.wasmGet", ref_of(recv), prop.to_s))
        end

        def set(recv, prop, value)
          @backend.call_js("__rbHost.wasmSet", ref_of(recv), prop.to_s, pack(value))
          nil
        end

        def call(recv, method, args)
          unpack(@backend.call_js("__rbHost.wasmCall", ref_of(recv), method.to_s, args.map { |a| pack(a) }))
        end

        # Apply a function ref directly (optionally with an explicit `this`).
        def apply(fn, this_arg, args)
          this_ref = this_arg.nil? ? nil : ref_of(this_arg)
          unpack(@backend.call_js("__rbHost.wasmApply", ref_of(fn), this_ref, args.map { |a| pack(a) }))
        end

        def construct(ctor, args)
          unpack(@backend.call_js("__rbHost.wasmNew", ref_of(ctor), args.map { |a| pack(a) }))
        end

        def typeof(value)
          @backend.call_js("__rbHost.wasmTypeof", ref_of(value))
        end

        def to_string(value)
          @backend.call_js("__rbHost.wasmToString", ref_of(value))
        end

        def strict_equal(a, b)
          @backend.call_js("__rbHost.wasmStrictEqual", ref_of(a), ref_of(b))
        end

        def js_null?(value)
          return value.nil? unless value.is_a?(JSValue)

          @backend.call_js("__rbHost.wasmIsNull", value.ref)
        end

        def instance_of?(value, ctor)
          @backend.call_js("__rbHost.wasmInstanceof", ref_of(value), ref_of(ctor))
        end

        # Make a JS function (returned as a ref) that calls back into the guest
        # with the given invoke-id when invoked.
        def make_callback(invoke_id)
          unpack(@backend.call_js("__rbHost.wasmMakeCallback", invoke_id.to_i))
        end

        def release(value)
          @backend.call_js("__rbHost.wasmReleaseRef", value.ref) if value.is_a?(JSValue)
          nil
        end

        # Ruby value -> wasm-tagged JS value. Public so the embedder's
        # #on_invoke dispatcher can pack the values it hands back into JS.
        def pack(value)
          case value
          when JSValue then {"__rb_js_ref" => value.ref}
          when nil, true, false, Integer, Float, String then value
          when Symbol then value.to_s
          when Array then value.map { |e| pack(e) }
          when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = pack(v) }
          else
            raise ArgumentError, "cannot pack #{value.class} for the wasm JS bridge"
          end
        end

        # wasm-tagged JS value -> Ruby value (JSValue for refs). Public for the
        # same reason as #pack.
        def unpack(value)
          case value
          when Hash
            if value.key?("__rb_js_ref")
              JSValue.new(value["__rb_js_ref"])
            elsif value.key?("__rb_undefined")
              nil
            elsif value.key?("__rb_bytes")
              value["__rb_bytes"]
            elsif value.key?("__rb_arraybuffer")
              value["__rb_arraybuffer"]
            else
              value.each_with_object({}) { |(k, v), h| h[k] = unpack(v) }
            end
          when Array then value.map { |e| unpack(e) }
          else value
          end
        end

        private

        def ref_of(value)
          return value.ref if value.is_a?(JSValue)

          raise ArgumentError, "expected a JSValue receiver, got #{value.inspect}"
        end
      end
    end
  end
end
