# frozen_string_literal: true

require "quickjs"

module Dommy
  module Js
    module Quickjs
      # Skips the per-crossing Ruby `Timeout.timeout` the quickjs gem wraps EVERY
      # host-function call in — every JS->Ruby DOM crossing (__rb_host_get /
      # _call / _set, …). That costs ~4us per crossing (≈40% of a DOM property
      # read: 9.8us -> 5.1us without it), and a DOM-heavy SPA (React/Apollo)
      # makes MILLIONS of them while hydrating — tens of seconds of pure Timeout
      # overhead, the dominant cost behind a slow page.
      #
      # It is redundant here: QuickJS's own C interrupt handler still
      # force-aborts a runaway JS execution at the eval timeout (independent of
      # this Ruby wrapper), and Dommy's host functions are bounded DOM
      # operations that never hang. DOMMY_JS_CROSSING_TIMEOUT=1 keeps the gem's
      # behavior, re-enabling the Ruby-callback-hang guard.
      #
      # Prepended to `::Quickjs`'s singleton rather than redefining the method:
      # the gem's own implementation stays in the ancestor chain (reachable with
      # `super`, visible in `::Quickjs.singleton_class.ancestors`), so the patch
      # can be seen and undone. Redefining it outright left no way to tell the
      # method had been replaced.
      module SkipCrossingTimeout
        def _with_timeout(_msec, proc, args)
          proc.call(*args)
        end
      end

      if ::Quickjs.respond_to?(:_with_timeout) && !Config.crossing_timeout?
        ::Quickjs.singleton_class.prepend(SkipCrossingTimeout)
      end

      # Binds HostBridge's abstract backend contract to the `quickjs` gem.
      #
      # Value-representation conformance: host_runtime.js now tags a top-level JS
      # `undefined` itself (`dehydrateTop` -> `{__rb_undefined:true}`) at the
      # JS->Ruby crossings, so the protocol no longer relies on the backend to
      # marshal a bare `undefined` to a sentinel — keeping it engine-neutral.
      # The `quickjs` gem happens to also deliver a bare `undefined` as the Ruby
      # symbol `:undefined`, which HostBridge#unwrap still accepts as a defensive
      # fallback (e.g. the `evaluate`/`tag` return path, which dehydrates without
      # the top-level tag); either way it maps to Dommy::Bridge::UNDEFINED. No
      # normalization is needed here.
      class Backend
        # Timeout and memory ceiling both differ from the gem's defaults, for
        # reasons Config documents.
        def initialize(**vm_opts)
          vm_opts = {timeout_msec: Config.timeout_msec, memory_limit: Config.memory_limit}.merge(vm_opts)
          @vm = ::Quickjs::VM.new(**vm_opts)
        end

        # True once the VM can no longer run JS safely: it hit out-of-memory (the
        # gem flags it "poisoned" — further eval may segfault) or was disposed.
        # Callers stop driving a poisoned VM (the page's JS is dead) instead of
        # letting the error crash the whole browser — browsing survives a page
        # whose JS ran out of memory, showing whatever rendered before it died.
        def poisoned?
          (@vm.respond_to?(:memory_poisoned?) && @vm.memory_poisoned?) ||
            (@vm.respond_to?(:disposed?) && @vm.disposed?)
        end

        # Every entry point that RUNS something in the VM goes through #guarded,
        # so a dead VM answers the same way whichever one a host reached for. It
        # used to guard three of the six: an inline script quietly did nothing
        # after an out-of-memory while an external (bytecode) one and #evaluate
        # raised "VM is poisoned" from a different place each time.
        #
        # Registering a host function or a listener is not guarded: none of them
        # runs JS, and they all happen while the VM is still alive.
        def eval(js) = guarded { @vm.eval_code(js, async: false) }

        # Compile JS source to reusable bytecode (parsed once, via a throwaway
        # VM). Run it on any number of fresh VMs with #run_compiled — far cheaper
        # than re-parsing the source per VM (the large host runtime / vendored
        # bundles are identical across VMs).
        def self.compile(source, filename: "<compiled>")
          ::Quickjs.compile(source, filename: filename)
        end

        # Process-global cache for the engine-internal runtime bundles run via
        # #run_bundle (host_runtime.js, observable_runtime.js). Kept separate
        # from ScriptCache (user-facing external scripts) so the two concerns
        # don't share a count/namespace.
        @bundle_cache = {}
        @bundle_mutex = Mutex.new

        def self.compiled_bundle(cache_key, source)
          @bundle_mutex.synchronize { @bundle_cache[cache_key] ||= compile(source, filename: cache_key.to_s) }
        end

        # Execute precompiled bytecode (a Quickjs::Runnable) on this VM in global
        # scope — equivalent to #eval of its source, without the parse cost.
        def run_compiled(runnable) = guarded { runnable.run(on: @vm) }

        # Run a source bundle that is identical across VMs (the bridge's host
        # runtime, the Observable polyfill): compile it to bytecode once per
        # process — keyed by `cache_key` — and run that on this VM. Lets the
        # engine-agnostic bridge reuse big bundles without knowing about
        # bytecode; the compile-once optimization stays here in the engine layer.
        def run_bundle(cache_key, source)
          run_compiled(self.class.compiled_bundle(cache_key, source))
        end

        # Async eval: the gem awaits the top-level result and drains the
        # microtask queue, so JS `await`/Promises resolve before returning.
        def eval_awaited(js) = guarded { @vm.eval_code(js, async: true) }

        # Install the ESM module resolver: a callable `(specifier, importer) ->
        # source String | { code:, as: } | nil` the engine consults for every
        # static/dynamic `import`. nil clears it (engine default loader).
        def module_loader=(callable)
          @vm.module_loader = callable
        end

        # Evaluate the module at `url` (resolved + fetched by the module loader).
        # The importer of its relative imports is `url`, so they resolve
        # correctly — unlike an inline module's synthetic filename.
        def import_module_url(url)
          guarded { @vm.import("* as __dommy_mod", filename: url, code_to_expose: "") }
        end

        def define_host_function(name, &block)
          @vm.define_function(name, &block)
        end

        def call_js(path, *args) = guarded { @vm.call(path, *args) }

        def drain_microtasks = guarded { @vm.drain_jobs! }

        # Register a handler for promise rejections that reach the microtask
        # queue with no `.catch` — frameworks (Turbo, …) often swallow these,
        # so surfacing them is essential for diagnosing failures.
        def on_unhandled_rejection(&block)
          @vm.on_unhandled_rejection(&block)
        end

        # Point the engine's promise-rejection hook at a JS function, named by an
        # expression evaluated once in global scope. Only defined when the engine
        # supports it, so callers can feature-detect with respond_to?.
        if ::Quickjs::VM.method_defined?(:promise_rejection_hook=)
          def promise_rejection_hook=(expression)
            @vm.promise_rejection_hook = expression
          end
        end

        # Register a handler for console.(log|info|debug|warn|error). The block
        # receives a log object (#severity / #to_s / #raw).
        def on_log(&block)
          @vm.on_log(&block)
        end

        def run_gc = guarded { @vm.gc! }

        def dispose
          @vm.dispose!
        end

        private

        # Run `block` unless the VM is dead, in which case the answer is nil —
        # the "browsing never crashes" contract: the page's JS has stopped, and
        # the host has already been told once (see EventLoop#note_halted).
        def guarded
          return if poisoned?

          yield
        end
      end
    end
  end
end
