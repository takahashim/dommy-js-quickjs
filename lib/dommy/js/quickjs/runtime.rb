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
          define_host_object("window", win)
          @bridge.window = win
          @backend.eval(<<~JS)
            globalThis.setTimeout = (fn, delay) => window.setTimeout(fn, delay);
            globalThis.clearTimeout = (id) => window.clearTimeout(id);
            globalThis.setInterval = (fn, delay) => window.setInterval(fn, delay);
            globalThis.clearInterval = (id) => window.clearInterval(id);
            globalThis.requestAnimationFrame = (fn) => window.requestAnimationFrame(fn);
            globalThis.cancelAnimationFrame = (id) => window.cancelAnimationFrame(id);
            globalThis.queueMicrotask = (fn) => window.queueMicrotask(fn);
          JS
          win
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
