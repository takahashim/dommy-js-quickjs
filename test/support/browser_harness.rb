# frozen_string_literal: true

module Dommy
  module Js
    # Test/dev harness for driving real frontend code (frameworks, bundles) on
    # Dommy + QuickJS. Bundles the things every such test needs:
    #
    #   - a parsed window + document host objects
    #   - browser bare-globals (Runtime#install_browser_globals)
    #   - an optional fetch stub (Dommy's __fetchy_stub__)
    #   - automatic capture of swallowed promise rejections (with JS backtraces)
    #     and console output — so failures surface instead of vanishing
    #   - a scheduler "pump" that drives deferred work (rAF/timeouts/microtasks)
    #
    #   h = BrowserHarness.new("<body>...</body>", fetch_stub: { "http://x/y" => {...} })
    #   h.load_script("vendor/turbo.umd.js")
    #   h.execute("...")
    #   h.pump
    #   assert_empty h.errors           # nothing was silently swallowed
    #   h.dispose
    class BrowserHarness
      attr_reader :window, :runtime, :errors, :logs

      def initialize(html = "<!DOCTYPE html><html><head></head><body></body></html>", fetch_stub: nil)
        @window = Dommy.parse(html)
        @window.__js_set__("__fetchy_stub__", fetch_stub) if fetch_stub
        @runtime = Dommy::Js::Quickjs::Runtime.new
        @errors = []
        @logs = []
        @runtime.on_unhandled_rejection { |err| @errors << err }
        @runtime.on_log { |log| @logs << log }
        @runtime.define_host_object("document", @window.document)
        @runtime.install_window(@window)
        @runtime.install_browser_globals
      end

      def execute(js) = @runtime.execute(js)
      def evaluate(js) = @runtime.evaluate(js)
      def load_script(path) = @runtime.execute(::File.read(path))

      # Register/extend the fetch stub (url => { status:, body:, contentType: }).
      def stub_fetch(map)
        existing = @window.__js_get__("__fetchy_stub__") || {}
        @window.__js_set__("__fetchy_stub__", existing.merge(map))
      end

      # Drive deferred work to completion: drain microtasks, advance the
      # deterministic clock (firing rAF/timeouts), repeat. Frameworks defer
      # rendering to the next repaint, so a single drain isn't enough.
      def pump(rounds: 20, step_ms: 16)
        rounds.times do
          @runtime.drain_microtasks
          @window.scheduler.advance_time(step_ms)
          @runtime.drain_microtasks
        end
        self
      end

      # Human-readable dump of captured rejections (message + JS stack) — handy
      # in an assertion message when a framework path silently fails.
      def error_report
        @errors.map { |e| "#{e.class}: #{e.message}\n  #{Array(e.backtrace).first(6).join("\n  ")}" }.join("\n")
      end

      def dispose = @runtime&.dispose
    end
  end
end
