# frozen_string_literal: true

require "quickjs"
require_relative "source_guard"

module Dommy
  module Js
    module Quickjs
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
        # The gem's default eval timeout is 100ms, which interrupts large
        # synchronous bridge loops (every property crossing is a Ruby call).
        DEFAULT_TIMEOUT_MSEC = 60_000

        def initialize(**vm_opts)
          vm_opts = {timeout_msec: DEFAULT_TIMEOUT_MSEC}.merge(vm_opts)
          @vm = ::Quickjs::VM.new(**vm_opts)
        end

        def eval(js)
          @vm.eval_code(js, async: false)
        rescue ::Quickjs::RuntimeError => e
          # A QuickJS codegen bug rejects `for-of` with a `yield` in the iterable
          # ("stack underflow") — rewrite that construct and retry once.
          raise unless SourceGuard.relevant_error?(e)

          guarded = SourceGuard.fix_for_of_yield(js)
          raise if guarded.equal?(js) || guarded == js

          @vm.eval_code(guarded, async: false)
        end

        # Compile JS source to reusable bytecode (parsed once, via a throwaway
        # VM). Run it on any number of fresh VMs with #run_compiled — far cheaper
        # than re-parsing the source per VM (the large host runtime / vendored
        # bundles are identical across VMs).
        def self.compile(source, filename: "<compiled>")
          ::Quickjs.compile(source, filename: filename)
        rescue ::Quickjs::RuntimeError => e
          # See #eval: work around the for-of/yield-in-iterable codegen bug.
          raise unless SourceGuard.relevant_error?(e)

          guarded = SourceGuard.fix_for_of_yield(source)
          raise if guarded.equal?(source) || guarded == source

          ::Quickjs.compile(guarded, filename: filename)
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
        def run_compiled(runnable)
          runnable.run(on: @vm)
        end

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
        def eval_awaited(js)
          @vm.eval_code(js, async: true)
        end

        # Install the ESM module resolver: a callable `(specifier, importer) ->
        # source String | { code:, as: } | nil` the engine consults for every
        # static/dynamic `import`. nil clears it (engine default loader).
        def module_loader=(callable)
          @vm.module_loader = callable
        end

        # Evaluate `source` as an ES module (its `import`s resolved through the
        # module loader). `* as` with no globalization runs it for side effects.
        def import_module(source)
          @vm.import("* as __dommy_mod", from: source, code_to_expose: "")
        end

        # Evaluate the module at `url` (resolved + fetched by the module loader).
        # The importer of its relative imports is `url`, so they resolve
        # correctly — unlike an inline module's synthetic filename.
        def import_module_url(url)
          @vm.import("* as __dommy_mod", filename: url, code_to_expose: "")
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

        # Register a handler for console.(log|info|debug|warn|error). The block
        # receives a log object (#severity / #to_s / #raw).
        def on_log(&block)
          @vm.on_log(&block)
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
