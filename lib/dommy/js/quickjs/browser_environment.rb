# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # What this QuickJS build is missing before a page can run in it: the bare
      # browser globals aliased onto the window, the timer globals routed into
      # Dommy's scheduler, and stand-ins for the two things the build omits
      # (Intl, WebAssembly).
      #
      # Separate from Runtime because it changes for its own reasons — a page
      # reaching for a global nobody aliased yet — which has nothing to do with
      # how the event loop is driven or how an engine exception becomes the
      # page's error.
      #
      # Each payload is a .js file next door rather than a Ruby heredoc, the way
      # the core bridge keeps host_runtime.js: it stays readable as JavaScript,
      # and #run_bundle compiles it to bytecode ONCE per process instead of
      # reparsing it for every VM.
      class BrowserEnvironment
        JS_DIR = ::File.join(__dir__, "js")
        private_constant :JS_DIR

        # Read at load time and frozen: the files never change at runtime, and a
        # per-VM read would undo the point of caching the compile.
        def self.payload(name)
          ::File.read(::File.join(JS_DIR, name)).freeze
        end
        private_class_method :payload

        TIMER_GLOBALS_JS = payload("timer_globals.js")
        BROWSER_GLOBALS_JS = payload("browser_globals.js")
        WINDOW_BUILTINS_JS = payload("window_builtins.js")
        INTL_POLYFILL_JS = payload("intl_polyfill.js")
        WASM_STUB_JS = payload("wasm_stub.js")

        def initialize(backend)
          @backend = backend
        end

        # setTimeout / setInterval / requestAnimationFrame / queueMicrotask, as
        # bare globals routed through the window (so they reach Dommy's
        # deterministic scheduler), plus the scheduling-site capture a throwing
        # callback is traced back through. Needs the window installed first.
        def install_timers
          run("timer_globals.js", TIMER_GLOBALS_JS)
        end

        # Everything a real frontend bundle expects to find on its own: the
        # aliased window globals, then the two polyfills, then the built-ins
        # mirrored onto the window. Order matters only in that the window must
        # already be installed.
        def install_globals
          run("browser_globals.js", BROWSER_GLOBALS_JS)
          run("intl_polyfill.js", INTL_POLYFILL_JS)
          install_wasm_stub
          run("window_builtins.js", WINDOW_BUILTINS_JS)
          self
        end

        # The WebAssembly stand-in on its own. Idempotent: the payload defines
        # nothing when `WebAssembly` already exists, so a host that asks for it
        # explicitly (the WPT harness wants the SharedArrayBuffer that
        # `Memory({shared:true})` yields) gets the same object install_globals
        # would have built.
        def install_wasm_stub
          run("wasm_stub.js", WASM_STUB_JS)
          self
        end

        private

        def run(cache_key, source)
          @backend.run_bundle(cache_key, source)
          self
        end
      end
    end
  end
end
