# frozen_string_literal: true

require "quickjs"

module Dommy
  module Js
    module Quickjs
      # Binds HostBridge's abstract backend contract to the `quickjs` gem.
      class Backend
        # The gem's default eval timeout is 100ms, which interrupts large
        # synchronous bridge loops (every property crossing is a Ruby call).
        DEFAULT_TIMEOUT_MSEC = 60_000

        def initialize(**vm_opts)
          vm_opts = {timeout_msec: DEFAULT_TIMEOUT_MSEC}.merge(vm_opts)
          @vm = ::Quickjs::VM.new(**vm_opts)
        end

        def eval(js)
          @vm.eval_code(js, async: false)
        end

        # Async eval: the gem awaits the top-level result and drains the
        # microtask queue, so JS `await`/Promises resolve before returning.
        def eval_awaited(js)
          @vm.eval_code(js, async: true)
        end

        def define_host_function(name, &block)
          @vm.define_function(name, &block)
        end

        def call_js(path, *args)
          @vm.call(path, *args)
        end

        def drain_microtasks
          @vm.drain_jobs!
        end

        # Register a handler for promise rejections that reach the microtask
        # queue with no `.catch` — frameworks (Turbo, …) often swallow these,
        # so surfacing them is essential for diagnosing failures.
        def on_unhandled_rejection(&block)
          @vm.on_unhandled_rejection(&block)
        end

        def run_gc
          @vm.gc!
        end

        def dispose
          @vm.dispose!
        end
      end
    end
  end
end
