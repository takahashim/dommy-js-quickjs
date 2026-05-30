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

      def initialize(html = "<!DOCTYPE html><html><head></head><body></body></html>")
        @harness = BrowserHarness.new(html)
        @harness.load_script(HARNESS)
        @harness.execute(<<~JS)
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
        @harness.execute(script)
        # Flip testharness's all_loaded so completion can fire, then drive async tests.
        @harness.execute('window.dispatchEvent(new Event("load"));')
        @harness.pump
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
