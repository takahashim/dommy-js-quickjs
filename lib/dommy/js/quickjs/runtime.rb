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
      # Implements the Dommy::Js::Runtime port (see that module for the contract)
      # by wiring four collaborators together and delegating to them:
      #
      #   Backend             the `quickjs` gem — eval, compile, the VM's state
      #   HostBridge          the engine-agnostic JS<->Ruby DOM bridge (core)
      #   BrowserEnvironment  the globals and polyfills a page expects to find
      #   EventLoop           microtasks + Dommy's scheduler, as one loop
      #   ErrorTranslator     an engine exception, as what the page should see
      #
      # What stays here is the port itself: script evaluation, and the wiring
      # that decides which collaborator answers a host's call.
      class Runtime
        def initialize(**vm_opts)
          @backend = Backend.new(**vm_opts)
          @bridge = Dommy::Js::HostBridge.new(@backend)
          @environment = BrowserEnvironment.new(@backend)
          @errors = ErrorTranslator.new(@backend, @bridge)
          @environment.install_error_rebuilder
          @loop = EventLoop.new(@backend, scheduler: -> { @window&.scheduler }) do |error|
            @callback_error_listener&.call(error)
          end
          @callback_error_listener = nil
          @track_rejections = Config.track_rejections?
          # Install the JS-side Promise rejection recorder (HostBridge registers
          # the __rb_record_rejection_detail sink it pushes to). The detail then
          # backfills the engine's detail-less report in #enrich_rejection.
          @backend.call_js("__rbHost.installRejectionTracker") if @track_rejections
        end

        def define_host_object(name, obj)
          @bridge.define_host_object(name, obj)
        end

        # Inject the Dommy window: seed it as the JS global, give the bridge the
        # realm it belongs to, route rejections and runaway callbacks back here,
        # and alias the bare timer globals onto it (so `setTimeout(fn, ms)` runs
        # through Dommy's deterministic scheduler — drive it with
        # `win.scheduler.advance_time(ms)`).
        def install_window(win)
          @window = win
          define_host_object("window", win)
          @bridge.window = win
          install_promise_rejection_hook
          wire_scheduler(win)
          @environment.install_timers
          win
        end

        # Expose the seeded interface constructors on a secondary window (an
        # iframe's contentWindow), so cross-window instanceof / defaultView work.
        # Call after install_window (the constructors must already be seeded).
        def expose_constructors_on(window_obj)
          @bridge.expose_constructors_on(window_obj)
        end

        # Wire the bare browser globals frameworks reach for, aliased onto the
        # installed window: self / location / history / navigator / storages /
        # CSS / fetch / addEventListener / .... Call after install_window. This
        # is what lets real frontend bundles (Turbo, …) run unmodified.
        def install_browser_globals
          @environment.install_globals
          self
        end

        # WPT-only scaffolding, part of the port's optional surface: the
        # harness's common/sab.js derives the SharedArrayBuffer constructor from
        # `new WebAssembly.Memory({shared:true}).buffer.constructor`. That is
        # what the WebAssembly stub's Memory already yields, so this is the same
        # install — named separately because a host asks for it explicitly, and a
        # no-op when #install_browser_globals already ran.
        def install_wasm_memory_shim
          @environment.install_wasm_stub
          self
        end

        # --- Running scripts ---

        # Run a script for side effects (no return value). Wrapped in an IIFE so
        # statements are allowed and the completion value is voided — otherwise a
        # trailing Promise expression would trip the gem's "unawaited Promise"
        # guard. Drains microtasks so queued .then work lands before returning.
        def execute(js)
          in_page_turn { @backend.eval("(function () {\n#{js}\n})();") }
        end

        # Load a script the way a browser <script> does: in GLOBAL scope, so its
        # top-level `var` / `function` / `let` declarations become globals. UMD /
        # "global" bundles rely on this — e.g. Vue's global build is literally
        # `var Vue = (function(){…})({})`, which an IIFE wrapper (execute) would
        # trap in function scope. Drains microtasks afterward.
        def load_script(js)
          in_page_turn { @backend.eval(discard_completion_value(js)) }
        end

        # Like #load_script, but compiles the source to bytecode once per
        # `cache_key` (an external script's URL) and reuses it across VMs —
        # avoiding a re-parse of large vendored bundles on every page load.
        def load_script_cached(js, cache_key:)
          in_page_turn do
            @backend.run_compiled(ScriptCache.compiled(cache_key, discard_completion_value(js)))
          end
        end

        # Install the ESM module resolver (see Backend#module_loader=). A
        # callable `(specifier, importer) -> source | {code:, as:} | nil`.
        def module_loader=(callable)
          @backend.module_loader = callable
        end

        # Evaluate an external module by URL (the loader fetches it); its
        # relative imports resolve against that URL. An inline module arrives
        # here too, seeded under a page URL by ScriptBoot so `import.meta.url`
        # resolves. Drains microtasks.
        def load_module_url(url)
          in_page_turn { @backend.import_module_url(url) }
        end

        # Evaluate JS and return its value, with DOM nodes decoded to Dommy
        # objects (rather than the empty Hash a raw proxy becomes crossing to
        # Ruby). Accepts either an expression (`document.title`) or a statement
        # body that uses `return` (`const x = ...; return x;`), run as an async
        # function body. Which one it is gets decided by compiling, not by
        # running and retrying (see #expression?). The result is awaited, so a
        # Promise resolves before returning.
        def evaluate(js)
          bump_dom_epoch
          evaluate_settled(expression?(js) ? parenthesized(js) : "(async () => {\n#{js}\n})()")
        end

        # Optional Runtime API: run a script with Ruby arguments as its
        # `arguments`. DOM objects cross as JS proxies (the same wire the bridge
        # uses for any Ruby->JS value), so `arguments[0].scrollIntoView()` works.
        # The wire payload is JSON spliced into the source and rehydrated
        # in-realm (`__rbHost.rehydrateArgs`), then spread into the script.
        def execute_with_args(js, args)
          wire = encode_args(args)
          in_page_turn { @backend.eval("(function () {\n#{with_arguments_js(js, wire)}\n})();") }
        end

        # Args-aware evaluate. Like #evaluate, the script is an expression
        # (`arguments[0].value`, the form Capybara's evaluate_script passes) or a
        # body that uses `return`; the decoded result is awaited.
        def evaluate_with_args(js, args)
          bump_dom_epoch
          body = expression?(js) ? "return #{parenthesized(js)};" : js
          evaluate_settled("(async function () {\n#{with_arguments_js(body, encode_args(args))}\n})()")
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

        # --- Driving the event loop (see EventLoop for what each one means) ---

        def drain_microtasks = @loop.drain_microtasks

        def settle(max_iterations: EventLoop::DEFAULT_MAX_ITERATIONS)
          @loop.settle(max_iterations: max_iterations)
          self
        end

        def run_until_idle(max_iterations: EventLoop::DEFAULT_MAX_ITERATIONS)
          @loop.run_until_idle(max_iterations: max_iterations)
          self
        end

        # --- Errors ---

        # An engine exception for a script's throw, rebuilt as a real Error
        # inside the realm so `event.error` is something the page can read.
        # Optional in the port contract; returns nil when it cannot be done.
        def rebuild_error(error) = @errors.rebuild_error(error)

        # Surface otherwise-swallowed JS promise rejections (see Backend).
        # Goes quiet once the JS hook is installed: both would fire for the same
        # rejection, and the hook carries strictly more.
        def on_unhandled_rejection(&block)
          # Decided when a rejection actually arrives, not now: a host registers
          # this before #install_window, which is where the hook goes in.
          relay = lambda do |error|
            next if js_rejection_hook?

            block.call(@track_rejections ? @errors.enrich_rejection(error) : error)
          end
          @backend.on_unhandled_rejection(&relay)
          self
        end

        # Whether rejections arrive through the JS hook. A host that also relays
        # #on_unhandled_rejection would otherwise report each rejection twice.
        def js_rejection_hook? = !!@js_rejection_hook

        # Observe a timer/rAF callback that was force-killed by the execution
        # timeout (a runaway busy loop). The host records it as a js_error; the
        # offending timer is already dropped by the scheduler so it cannot
        # re-stall. Optional in the port contract (guard with respond_to?).
        def on_callback_error(&block)
          @callback_error_listener = block
          self
        end

        # Observe console.* output (see Backend).
        def on_log(&block)
          @backend.on_log(&block)
          self
        end

        # --- Introspection and teardown ---

        # Handle-oriented JS access for a wasm guest (see WasmBridge). Memoized
        # so the guest's `__rbWasmInvoke` dispatcher (installed via #on_invoke)
        # stays registered for the VM's lifetime.
        def wasm_bridge
          @wasm_bridge ||= WasmBridge.new(@backend)
        end

        # Run JS GC then drain, so FinalizationRegistry cleanup callbacks fire and
        # release handles for proxies that are no longer referenced.
        def collect_garbage
          @backend.run_gc
          @backend.drain_microtasks
        end

        # Live handle count (introspection for lifetime tests).
        def registered_count = @bridge.registered_count

        # Snapshot bridge crossing counts when DOMMY_JS_BRIDGE_PROFILE=1.
        def bridge_crossing_counts(limit: nil) = @bridge.crossing_counts(limit: limit)

        def reset_bridge_crossing_counts
          @bridge.reset_crossing_counts
          self
        end

        def dispose = @backend.dispose

        private

        # A runaway timer/rAF callback (busy loop) is force-killed by the gem's
        # eval timeout, surfacing as a Quickjs::InterruptedError out of the host
        # call. Route it through the scheduler's error hook so it is recorded as
        # a js_error and dropped, not propagated as a fatal crash (browsing must
        # never crash). Genuine host bugs (any other error) still propagate.
        #
        # The microtask checkpoint is the other half of the wiring: draining
        # after EACH task (not once per batch of due timers) is what the event
        # loop processing model requires.
        def wire_scheduler(win)
          return unless win.respond_to?(:scheduler) && win.scheduler

          win.scheduler.timer_error_handler = method(:handle_timer_error)
          win.scheduler.microtask_checkpoint = method(:drain_microtasks)
        end

        # Hand rejections to the JS hook rather than to a Ruby callback, when the
        # engine has one. It is called with the promise and the reason as the
        # values the page threw, which is the whole point: an exception the
        # engine already converted has lost both, and the page ends up with an
        # object it cannot read. The hook also reports the other half of HTML's
        # tracking, `rejectionhandled`, which a Ruby callback never sees.
        #
        # No-op on an engine without it; #on_unhandled_rejection then stays the
        # route, with the losses that implies.
        def install_promise_rejection_hook
          return unless @backend.respond_to?(:promise_rejection_hook=)

          @backend.promise_rejection_hook = "__rbHost.onPromiseRejection"
          @js_rejection_hook = true
        rescue ::StandardError
          @js_rejection_hook = false
        end

        # Scheduler hook: a timer/rAF callback raised. A JS-execution error —
        # the callback threw (Quickjs::RuntimeError) or was force-killed for
        # running too long (Quickjs::InterruptedError < RuntimeError) — must not
        # escape its dispatch (WHATWG: a timer callback's exception is reported,
        # the event loop keeps running). Record it and return truthy so the
        # scheduler drops the timer and browsing continues. A non-JS error is a
        # genuine host bug: return falsy so it propagates.
        def handle_timer_error(error, timer)
          return false unless error.is_a?(::Quickjs::RuntimeError)

          # An out-of-memory in a timer callback poisons the whole VM: the page's
          # JS is dead from here on, so flag it (and report once) — not just this
          # one callback.
          @loop.note_halted_if_poisoned(error)
          @callback_error_listener&.call(@errors.with_timer_origin(error, timer))
          true
        end

        # A classic script's completion value is discarded by a browser, but the
        # gem converts whatever the eval returned and REFUSES a pending Promise
        # ("An unawaited Promise was returned to the top-level"). A script whose
        # last statement is an assignment of one — `window.p = new Promise(…);`,
        # which is how a page publishes a promise for a later script to await —
        # therefore reached the page as an uncaught error, and a testharness page
        # that saw it reported no results at all.
        #
        # #execute solves this by wrapping in an IIFE, which #load_script cannot
        # do: its declarations have to land in global scope. Append a statement
        # that evaluates to undefined instead. The leading newline is what keeps
        # it out of a trailing line comment, and no declaration moves scope.
        def discard_completion_value(js) = "#{js}\n;void 0;"

        # One turn of handing the page something to run. Ruby may have mutated the
        # DOM since JS last ran, so the bridge's attribute snapshots are
        # invalidated first; then the work runs; then queued `.then` work lands
        # before the caller gets control back.
        #
        # Every entry point that gives the page code goes through here, so a new
        # one cannot forget either half. Forgetting the first would be the quiet
        # kind of bug: the page reads attribute values that are no longer true,
        # and nothing raises.
        def in_page_turn
          bump_dom_epoch
          yield
          drain_microtasks
          nil
        end

        # Ruby -> JS entry: Ruby code (test drivers, script boot) may have
        # mutated the DOM since JS last ran, so invalidate the bridge's
        # attribute snapshots (see host_runtime.js). A no-op before the host
        # runtime is installed.
        def bump_dom_epoch
          @backend.eval("globalThis.__rbHost && globalThis.__rbHost.bumpDomEpoch();")
          nil
        end

        # Evaluate `expr` to its awaited value, driving the event loop so a result
        # that depends on a TASK (a fetch's setTimeout(0) delivery, a setTimeout)
        # settles first. The gem's top-level await (js_std_await) only drains the
        # engine's job queue, never Dommy's scheduler — so awaiting a task-resolved
        # promise directly deadlocks in C. Instead: store the result, run the
        # event loop over everything due NOW (microtask checkpoint + due tasks and
        # the tasks they chain), then await the now-settled promise (which returns
        # immediately and still surfaces a rejection as a Ruby raise, as before).
        def evaluate_settled(expr)
          # `void 0` keeps the completion value off the promise, so the eval
          # doesn't trip the gem's "unawaited Promise at top-level" guard.
          @backend.eval("globalThis.__rbEvalP = Promise.resolve(#{expr}); void 0;")
          @loop.drive_due_now
          @bridge.decode(eval_tagged("await globalThis.__rbEvalP"))
        end

        def eval_tagged(inner_expr)
          @backend.eval_awaited("__rbHost.tag(#{inner_expr});")
        end

        # Whether `js` is a single expression, found by compiling it — nothing
        # runs. Running it and retrying as a body on SyntaxError could not tell
        # a parse error from one the script throws (`JSON.parse("{")`), and the
        # retry then ran the script's side effects a second time.
        def expression?(js)
          Backend.compile(parenthesized(js))
          true
        rescue ::Quickjs::SyntaxError
          false
        end

        # `js` as a parenthesized expression, a trailing `;` dropped. The
        # newlines keep a trailing line comment from swallowing the `)`.
        def parenthesized(js) = "(\n#{js.strip.sub(/;\s*\z/, "")}\n)"

        # Script arguments as the bridge's JSON wire payload.
        def encode_args(args) = JSON.generate(@bridge.encode(Array(args)))

        # A script body wrapped so `arguments` are the wire payload rehydrated
        # in-realm (DOM handles become JS proxies). The payload is spliced into
        # the source as a JSON literal and held in a function-local `var`, so
        # nested calls can't collide and there is no global to clean up.
        def with_arguments_js(js, wire_json)
          "var __rbScriptArgs = __rbHost.rehydrateArgs(#{wire_json});\n" \
            "return (function () {\n#{js}\n}).apply(this, __rbScriptArgs);"
        end
      end
    end
  end
end
