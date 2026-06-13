# frozen_string_literal: true

require_relative "browser_harness"

module Dommy
  module Js
    # Runs Web Platform Tests' `testharness.js` against the bridge and harvests
    # per-subtest results — the conformance lens that pins the JS-facing DOM.
    #
    #   wpt = WptHarness.new
    #   results = wpt.run_file("path/to/foo.any.js")   # or wpt.run("<test script>")
    #   results.reject(&:pass?)                         # the failing subtests
    #   wpt.dispose
    #
    # `.any.js` / `.window.js` WPT files are pure test scripts (no HTML), so they
    # run directly. For `.html` tests, pass the inline `<script>` body to #run.
    #
    # Mechanics: testharness defers completion until the page "load" event
    # (`all_loaded`) AND all tests settle. We dispatch a synthetic load event and
    # pump the deterministic scheduler so async_test/promise_test resolve, then
    # read the results the completion callback stashed.
    class WptHarness
      HARNESS = ::File.expand_path("../fixtures/testharness.js", __dir__)

      # A single subtest result. status follows testharness Test.statuses:
      # 0 PASS, 1 FAIL, 2 TIMEOUT, 3 NOTRUN.
      Result = Struct.new(:name, :status, :message) do
        STATUS_NAMES = %w[PASS FAIL TIMEOUT NOTRUN].freeze
        def pass? = status.zero?
        def status_name = STATUS_NAMES[status] || "UNKNOWN(#{status})"
        def to_s = "[#{status_name}] #{name}#{message ? " — #{message}" : ""}"
      end

      def self.available? = ::File.exist?(HARNESS)

      def initialize(html = "<!DOCTYPE html><html><head></head><body></body></html>", fetch_stub: nil, iframe_docs: nil)
        @harness = BrowserHarness.new(html, fetch_stub: fetch_stub, iframe_docs: iframe_docs)
        # WPT's common/sab.js derives the SharedArrayBuffer constructor through
        # WebAssembly.Memory; install that test-only shim for the WPT realm.
        @harness.runtime.install_wasm_memory_shim
        @harness.load_script(HARNESS)
        @harness.execute(<<~JS)
          // We harvest results programmatically via add_completion_callback, so
          // testharness's visual output is dead weight — and worse, it renders
          // each subtest name into the DOM via document.createTextNode. WPT names
          // embed the test input verbatim (URL cases carry literal NUL/control
          // chars), and the libxml2-backed text node rejects null bytes, which
          // would crash completion and zero out the whole file's results.
          setup({ output: false });
          globalThis.__wptResults = null;
          add_completion_callback((tests) => {
            globalThis.__wptResults = tests.map((t) => ({ name: t.name, status: t.status, message: t.message }));
          });
        JS
        @ran = false
      end

      # Run a WPT test script (one file's worth of test()/async_test()/... calls)
      # and return its subtest Results. One-shot per instance — testharness fires
      # completion once.
      def run(script)
        raise "WptHarness#run is one-shot per instance" if @ran

        @ran = true
        # HTML "named access on the Window": an element with an `id` is exposed
        # as a bare global (`<div id=foo>` → `foo`). Our window proxy is distinct
        # from the engine's globalThis, so bare identifiers can't reach it; mirror
        # the document's id'd elements onto globalThis (without shadowing an
        # existing global) so tests that reference elements by bare id resolve.
        @harness.execute(<<~JS)
          for (const __el of document.querySelectorAll("[id]")) {
            const __id = __el.id;
            if (__id && !(__id in globalThis)) {
              try { Object.defineProperty(globalThis, __id, { value: __el, configurable: true, writable: true }); } catch (__e) {}
            }
          }
        JS
        @harness.execute(script)
        # Flip testharness's all_loaded so completion can fire, then drive async tests.
        @harness.execute('window.dispatchEvent(new Event("load"));')
        @harness.pump
        # If some async_test never settled (e.g. a MutationObserver record we
        # don't deliver), completion never fires and ALL results are lost. Drive
        # the deterministic clock past testharness's harness timeout (10s) so its
        # timeout fires — marking the stragglers TIMEOUT and running the
        # completion callback — and the tests that DID finish are still harvested.
        # Advance in fine 100ms steps (not one big jump) so CHAINS of timers —
        # an async iterable whose next() resolves via a 400ms setTimeout that, on
        # firing, schedules the following one — all fire in sequence rather than
        # stalling after the first two. 250 rounds = 25s, comfortably past the
        # 10s harness timeout for anything genuinely stuck.
        if @harness.evaluate("globalThis.__wptResults === null")
          @harness.pump(rounds: 250, step_ms: 100)
        end
        Array(@harness.evaluate("globalThis.__wptResults"))
          .map { |r| Result.new(r["name"], r["status"], r["message"]) }
      end

      def run_file(path) = run(::File.read(path))

      # JS errors/rejections captured during the run (swallowed framework errors
      # surface here — see BrowserHarness#on_unhandled_rejection).
      def errors = @harness.errors

      def dispose = @harness.dispose
    end
  end
end
