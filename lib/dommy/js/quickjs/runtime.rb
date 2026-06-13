# frozen_string_literal: true

module Dommy
  module Js
    module Quickjs
      # Public entry point: a JS runtime that can drive a Dommy DOM.
      #
      #   rt = Dommy::Js::Quickjs::Runtime.new
      #   rt.define_host_object("document", win.document)
      #   rt.evaluate('document.querySelector("h1").textContent')  #=> "..."
      #
      # Wires the QuickJS Backend to the engine-agnostic HostBridge, seeded with
      # the Dommy method manifest.
      class Runtime
        def initialize(**vm_opts)
          @backend = Backend.new(**vm_opts)
          @bridge = Dommy::Js::HostBridge.new(@backend)
        end

        def define_host_object(name, obj)
          @bridge.define_host_object(name, obj)
        end

        # Inject the Dommy window and alias the bare browser timer globals to it,
        # so `setTimeout(fn, ms)` routes into Dommy's deterministic scheduler.
        # Drive callbacks with `win.scheduler.advance_time(ms)`. `window.setTimeout`
        # already works via the Window manifest; this also wires the unqualified
        # globals browsers expose.
        def install_window(win)
          @window = win
          define_host_object("window", win)
          @bridge.window = win
          @backend.eval(<<~JS)
            globalThis.setTimeout = (fn, delay) => window.setTimeout(fn, delay);
            globalThis.clearTimeout = (id) => window.clearTimeout(id);
            globalThis.setInterval = (fn, delay) => window.setInterval(fn, delay);
            globalThis.clearInterval = (id) => window.clearInterval(id);
            globalThis.requestAnimationFrame = (fn) => window.requestAnimationFrame(fn);
            globalThis.cancelAnimationFrame = (id) => window.cancelAnimationFrame(id);
            // queueMicrotask must share the engine's promise-job (microtask)
            // queue so its callbacks are FIFO-ordered with Promise reactions
            // (the WHATWG single-microtask-queue model). Routing through the
            // Ruby scheduler instead would drain on a separate pass, reordering
            // it after all native promise jobs.
            globalThis.queueMicrotask = (fn) => {
              if (typeof fn !== "function") throw new TypeError("queueMicrotask requires a function");
              Promise.resolve().then(() => { fn(); });
            };
          JS
          win
        end

        # Expose the seeded interface constructors on a secondary window (an
        # iframe's contentWindow), so cross-window instanceof / defaultView work.
        # Call after install_window (the constructors must already be seeded).
        def expose_constructors_on(window_obj)
          @bridge.expose_constructors_on(window_obj)
        end

        # Run a script for side effects (no return value). Wrapped in an IIFE so
        # statements are allowed and the completion value is voided — otherwise a
        # trailing Promise expression would trip the gem's "unawaited Promise"
        # guard. Drains microtasks so queued .then work lands before returning.
        def execute(js)
          @backend.eval("(function () {\n#{js}\n})();")
          drain_microtasks
          nil
        end

        # Load a script the way a browser <script> does: in GLOBAL scope, so its
        # top-level `var` / `function` / `let` declarations become globals. UMD /
        # "global" bundles rely on this — e.g. Vue's global build is literally
        # `var Vue = (function(){…})({})`, which an IIFE wrapper (execute) would
        # trap in function scope. Drains microtasks afterward.
        def load_script(js)
          @backend.eval(js)
          drain_microtasks
          nil
        end

        # Like #load_script, but compiles the source to bytecode once per
        # `cache_key` (an external script's URL) and reuses it across VMs —
        # avoiding a re-parse of large vendored bundles on every page load.
        def load_script_cached(js, cache_key:)
          @backend.run_compiled(ScriptCache.compiled(cache_key, js))
          drain_microtasks
          nil
        end

        # Install the ESM module resolver (see Backend#module_loader=). A
        # callable `(specifier, importer) -> source | {code:, as:} | nil`.
        def module_loader=(callable)
          @backend.module_loader = callable
        end

        # Evaluate an inline `<script type="module">` body as an ES module (run
        # for side effects). Bare specifiers / absolute paths in its imports
        # resolve through the module loader. Drains microtasks afterward.
        def load_module(source)
          @backend.import_module(source)
          drain_microtasks
          nil
        end

        # Evaluate an external module by URL (the loader fetches it); its
        # relative imports resolve against that URL. Drains microtasks.
        def load_module_url(url)
          @backend.import_module_url(url)
          drain_microtasks
          nil
        end

        # Evaluate JS and return its value, with DOM nodes decoded to Dommy
        # objects (rather than the empty Hash a raw proxy becomes crossing to
        # Ruby). Accepts either an expression (`document.title`) or a statement
        # body that uses `return` (`const x = ...; return x;`): the expression
        # form is tried first and, on a syntax error, retried as an async
        # function body. Syntax errors are compile-time so the failed first
        # attempt runs nothing. The result is awaited, so a Promise resolves
        # before returning.
        def evaluate(js)
          @bridge.decode(eval_tagged("await (#{js.strip.sub(/;\s*\z/, "")})"))
        rescue ::Quickjs::SyntaxError
          @bridge.decode(eval_tagged("await (async () => {\n#{js}\n})()"))
        end

        def drain_microtasks
          @backend.drain_microtasks
        end

        # Drive the document lifecycle: set `document.readyState` and fire the
        # milestone events (`readystatechange`, then `DOMContentLoaded` on
        # "interactive" / `load` on "complete"), then drain microtasks so the
        # listeners settle. Lets a host replay the real load sequence so code
        # that waits on document readiness (framework startup, `ready` handlers)
        # runs the deferred path. The document defaults to "complete", so call
        # `set_document_ready_state("loading")` BEFORE loading such code to
        # exercise the waiting path.
        def set_document_ready_state(state)
          @window&.document&.__internal_set_ready_state__(state)
          drain_microtasks
          self
        end

        # Handle-oriented JS access for a wasm guest (see WasmBridge). Memoized
        # so the guest's `__rbWasmInvoke` dispatcher (installed via #on_invoke)
        # stays registered for the VM's lifetime.
        def wasm_bridge
          @wasm_bridge ||= WasmBridge.new(@backend)
        end

        # Drive the event loop to quiescence: drain the native microtask queue,
        # then advance the deterministic scheduler to its next due timer and drain
        # again, repeating until no timer is pending. This is the single
        # deterministic "settle everything" entry point a host uses after an eval
        # (mirroring a `drain_async!`): every queued microtask runs and every
        # scheduled timer fires, in WHATWG order (microtasks before each timer).
        # `max_iterations` bounds runaway timer loops (e.g. a self-rescheduling
        # setInterval).
        def run_until_idle(max_iterations: 1000)
          sched = @window&.scheduler
          max_iterations.times do
            drain_microtasks
            break unless sched

            next_at = sched.next_due_timer_at
            break unless next_at

            sched.advance_time(next_at - sched.now_ms)
            drain_microtasks
          end
          self
        end

        # Settle the work that is READY at the current virtual time: drain
        # microtasks, run timers already due now (`setTimeout(0)` chains), and
        # flush pending `requestAnimationFrame` callbacks by advancing to their
        # frame boundary — but do NOT jump the clock to a not-yet-due
        # `setTimeout(300)` (that needs an explicit `advance_time(300)`). This is
        # the "let promises and animation frames resolve" entry point; `bound`
        # caps a self-rescheduling rAF loop.
        def settle(max_iterations: 1000)
          sched = @window&.scheduler
          max_iterations.times do
            drain_microtasks
            break unless sched

            before = sched.now_ms
            sched.advance_time(0) # run due-now timers + microtasks, no clock jump
            drain_microtasks

            raf_at = sched.next_animation_frame_at
            if raf_at && raf_at > sched.now_ms
              sched.advance_time(raf_at - sched.now_ms) # advance to the frame, run rAF
              drain_microtasks
              next
            end

            break if sched.now_ms == before
          end
          self
        end

        # Surface otherwise-swallowed JS promise rejections (see Backend).
        def on_unhandled_rejection(&block)
          @backend.on_unhandled_rejection(&block)
          self
        end

        # Observe console.* output (see Backend).
        def on_log(&block)
          @backend.on_log(&block)
          self
        end

        # Wire the bare browser globals frameworks reach for, aliased onto the
        # installed window: self / location / history / navigator / storages /
        # CSS / fetch / addEventListener / .... Call after install_window. This
        # is what lets real frontend bundles (Turbo, …) run unmodified.
        def install_browser_globals
          @backend.eval(<<~JS)
            globalThis.self = globalThis;
            // Top-level window: parent/top are the window itself (spec), so
            // frame-walking loops terminate instead of dereferencing undefined.
            globalThis.parent = globalThis;
            globalThis.top = globalThis;
            globalThis.location = window.location;
            globalThis.history = window.history;
            globalThis.navigator = window.navigator;
            globalThis.sessionStorage = window.sessionStorage;
            globalThis.localStorage = window.localStorage;
            globalThis.CSS = window.CSS;
            globalThis.fetch = (...args) => window.fetch(...args);
            globalThis.addEventListener = (...args) => window.addEventListener(...args);
            globalThis.removeEventListener = (...args) => window.removeEventListener(...args);
            globalThis.dispatchEvent = (event) => window.dispatchEvent(event);
            // The window IS the global object, so JS built-in constructors and
            // namespaces are also `window` properties (`window.String`,
            // `window.Number`, …). Mirror them as own props on the window proxy
            // so code that reads constructors off `window` (e.g. the WPT
            // reflection harness's `window[type]` casts) resolves them.
            for (const __n of [
              "String", "Boolean", "Number", "BigInt", "Symbol", "Object", "Array",
              "Function", "Date", "RegExp", "Promise", "Map", "Set", "WeakMap",
              "WeakSet", "Math", "JSON", "Reflect", "Proxy", "Error", "TypeError",
              "RangeError", "SyntaxError", "Infinity", "NaN", "undefined",
              "parseInt", "parseFloat", "isNaN", "isFinite", "globalThis",
            ]) {
              try { window[__n] = globalThis[__n]; } catch (__e) {}
            }
            // Minimal WebAssembly.Memory: the engine provides a real
            // SharedArrayBuffer but no WebAssembly, and WPT's `common/sab.js`
            // derives the SAB constructor from
            // `new WebAssembly.Memory({shared:true}).buffer.constructor`. A
            // Memory whose `.buffer` is a SharedArrayBuffer is enough to let
            // those tests (encodeInto, TextDecoder copy, …) exercise shared
            // buffers with the real codec logic.
            if (typeof globalThis.WebAssembly === "undefined" && typeof globalThis.SharedArrayBuffer === "function") {
              globalThis.WebAssembly = {
                Memory: function (opts) {
                  const bytes = ((opts && opts.initial) || 0) * 65536;
                  this.buffer = (opts && opts.shared)
                    ? new SharedArrayBuffer(bytes)
                    : new ArrayBuffer(bytes);
                },
              };
            }
          JS
          self
        end

        # Run JS GC then drain, so FinalizationRegistry cleanup callbacks fire and
        # release handles for proxies that are no longer referenced.
        def collect_garbage
          @backend.run_gc
          @backend.drain_microtasks
        end

        # Live handle count (introspection for lifetime tests).
        def registered_count
          @bridge.registered_count
        end

        def dispose
          @backend.dispose
        end

        private

        def eval_tagged(inner_expr)
          @backend.eval_awaited("__rbHost.tag(#{inner_expr});")
        end
      end
    end
  end
end
