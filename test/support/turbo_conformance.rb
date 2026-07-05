# frozen_string_literal: true

require "json"
require_relative "browser_harness"

module Dommy
  module Js
    # Runs @hotwired/turbo's own UNIT suite (src/tests/unit) against the bridge
    # and harvests per-test results — the Turbo analogue of StimulusConformance.
    #
    #   TurboConformance.run_all   # => [Result, …] across every unit test
    #
    # Only Turbo's unit suite is portable here: its functional/ and integration/
    # tests drive a real browser via Playwright against a Koa dev server with
    # cross-page navigation, which a single QuickJS VM can't host. Those
    # behaviors are covered instead by test/dommy/js/test_turbo_integration.rb.
    #
    # The suite is vendored as a single esbuild bundle (test/fixtures/
    # turbo-tests.umd.js) plus a mocha/chai shim (support/mocha_shim.js); see
    # script/build_turbo_tests.sh for how the bundle is regenerated.
    #
    # Each test runs in its OWN freshly created VM (see StimulusConformance for
    # the rationale — the bridge's handle/callback tables never evict, so a
    # per-test VM keeps memory bounded and crash-free at the cost of re-parsing
    # the bundle each time).
    class TurboConformance
      BUNDLE = ::File.expand_path("../fixtures/turbo-tests.umd.js", __dir__)
      SHIM   = ::File.expand_path("mocha_shim.js", __dir__)
      PAGE   = "<!DOCTYPE html><html><head></head><body></body></html>"

      # A run promise that never settles is bounded by the shim's per-test
      # timeout; this caps the pump.
      MAX_PUMPS = 400

      Result = Struct.new(:module_name, :name, :status, :message) do
        def pass? = status == "pass"
        def skip? = status == "skip"
        def todo? = status == "todo" || status == "todo-pass"
        # Counts toward the conformance denominator (excludes skips/todos).
        def runnable? = !skip? && !todo?
        def to_s = "[#{status.to_s.upcase}] #{module_name} :: #{name}#{message ? " — #{message}" : ""}"
      end

      class << self
        def available? = ::File.exist?(BUNDLE) && ::File.exist?(SHIM)

        # Every (module, test) the bundle registers — read once from a throwaway VM.
        def manifest
          rt, = boot
          JSON.parse(rt.evaluate("JSON.stringify(Mocha.__manifest())"))
        ensure
          rt&.dispose
        end

        # Distinct module (file) names, in registration order.
        def module_names
          manifest.map { |t| t["module"] }.uniq
        end

        # Run a single test in a fresh VM; returns its Result. A test whose VM
        # exhausts the (default) heap raises Quickjs::RuntimeError — recorded as a
        # failure rather than aborting the run.
        def run_test(module_name, test_name)
          rt, win = boot
          rt.execute(<<~JS)
            globalThis.__done = false;
            Mocha.__runOne(#{module_name.to_json}, #{test_name.to_json})
              .then(() => { globalThis.__done = true; })
              .catch((e) => { globalThis.__err = String((e && e.stack) || e); globalThis.__done = true; });
          JS
          MAX_PUMPS.times do
            break if rt.evaluate("globalThis.__done")

            rt.drain_microtasks
            win.scheduler.advance_time(16)
            rt.drain_microtasks
          end
          raw = rt.evaluate("JSON.stringify(globalThis.__mochaResults || [])")
          r = JSON.parse(raw).first
          if r
            Result.new(module_name, r["name"].to_s.split(" :: ").last, r["status"], r["message"])
          else
            Result.new(module_name, test_name, "fail", "no result (timed out without settling)")
          end
        rescue ::Quickjs::RuntimeError => e
          Result.new(module_name, test_name, "fail", "VM error: #{e.message[0, 80]}")
        ensure
          rt&.dispose
        end

        # Run every test (each in its own VM) and return all Results. Yields each
        # Result as it completes when a block is given (for progress reporting).
        def run_all
          manifest.map do |t|
            result = run_test(t["module"], t["name"])
            yield result if block_given?
            result
          end
        end

        private

        # A fresh runtime + window with the shim and test bundle loaded.
        def boot
          rt = Dommy::Js::Quickjs::Runtime.new
          win = Dommy.parse(PAGE)
          rt.define_host_object("document", win.document)
          rt.install_window(win)
          rt.install_browser_globals
          rt.execute(::File.read(SHIM))
          rt.execute(::File.read(BUNDLE))
          [rt, win]
        end
      end
    end
  end
end
