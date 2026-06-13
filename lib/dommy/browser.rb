# frozen_string_literal: true

module Dommy
  # A lightweight test browser: parse HTML, build window/document, run its
  # classic `<script>` tags (inline + external via a resources adapter), fire
  # DOMContentLoaded/load, and collect JS errors / console output. For
  # standalone HTML + JS (bundled SPA, fixture HTML); the Rack/Rails entry point
  # is `Dommy::Rack::Session` (a later phase).
  #
  #   Dommy::Browser.open(html, resources: Dommy::Resources.static("/app.js" => "...")) do |b|
  #     b.settle
  #     b.evaluate('document.querySelector("h1").textContent')
  #   end
  #
  # JS errors are not swallowed: in strict mode (default) any unhandled rejection
  # or uncaught script error fails at the next checkpoint (after boot, after
  # `settle`, at dispose). Wrap intentional errors in `allow_js_errors { … }`.
  class Browser
    # Capybara-vocabulary finding / scoping / field interaction / click /
    # matchers come from the shared interaction layer; each interaction's events
    # are dispatched Ruby-side (synchronously invoking JS handlers), then
    # `after_interaction` drains the runtime's microtasks so promise reactions
    # settle before the next line.
    include Dommy::Interaction::Driver

    # Raised in strict mode when JS errors were collected and not acknowledged.
    class JsError < StandardError
      attr_reader :causes

      def initialize(causes)
        @causes = causes
        super(build_message(causes))
      end

      private

      def build_message(causes)
        lines = causes.map { |e| "  #{e.class}: #{e.message}" }
        "#{causes.length} uncaught JS error(s):\n#{lines.join("\n")}"
      end
    end

    attr_reader :window, :runtime, :js_errors, :console

    # Build a browser and (unless `execute_scripts: false`) boot its scripts. In
    # block form the browser is yielded and disposed afterward, returning the
    # block value.
    def self.open(html, **opts)
      browser = new(html, **opts)
      return browser unless block_given?

      begin
        yield browser
      ensure
        browser.dispose
      end
    end

    def initialize(html, url: "http://localhost/", resources: nil, execute_scripts: true, strict: true, settle: true)
      @resources = resources
      @strict = strict
      @js_errors = []
      @console = []
      @acknowledged = 0
      @allow_errors = false
      @disposed = false

      @window = Dommy.parse(html)
      @window.location.__internal_set_url__(url) if url

      @runtime = Js::Quickjs::Runtime.new
      @runtime.on_unhandled_rejection { |err| @js_errors << err }
      @runtime.on_log { |log| @console << log }
      @runtime.define_host_object("document", @window.document)
      @runtime.install_window(@window)
      @runtime.install_browser_globals
      @window.globals["__fetch_handler__"] = Resources::FetchHandler.new(@resources) if @resources

      if execute_scripts
        Js::Quickjs::ScriptBoot.run_document_scripts(
          @runtime, @window.document, resources: @resources, on_error: ->(e) { @js_errors << e }
        )
        # Leave the page in a ready state: run on-load promises, due-now timers,
        # and rAF (not future timers). `settle: false` observes it mid-flight.
        @runtime.settle if settle
      end
      check_js_errors!
    end

    def document = @window.document

    # Current document HTML (serialized).
    def html = @window.document.document_element&.outer_html

    # Evaluate an expression / statement body and return the decoded value.
    def evaluate(js)
      result = @runtime.evaluate(js)
      check_js_errors!
      result
    end

    # Run JS for side effects.
    def execute(js)
      @runtime.execute(js)
      check_js_errors!
      nil
    end

    # Settle the work ready at the current virtual time: drain microtasks, run
    # due-now timers, flush requestAnimationFrame. Does NOT fire a future
    # `setTimeout(300)` — use `advance_time(300)` for debounce/throttle.
    def settle
      @runtime.settle
      check_js_errors!
      self
    end

    # Advance virtual time by `ms`, running timers that come due, then settle.
    def advance_time(ms)
      @window.scheduler.advance_time(ms)
      @runtime.drain_microtasks
      check_js_errors!
      self
    end

    # An interaction's events have been dispatched (Ruby-side, synchronously
    # invoking JS handlers); drain the runtime's microtasks so promise reactions
    # land before the next line, then enforce strict mode.
    def after_interaction
      @runtime.drain_microtasks
      check_js_errors!
    end

    # Click a submit-capable button. The button's click event fires (JS may
    # handle / preventDefault it); if it is an un-prevented submit button, the
    # form's `submit` event is dispatched too (a SPA's JS handles it). Real
    # navigation on an un-prevented submit is a Session concern (out of scope).
    def click_button(locator)
      button = finder.find_button(locator)
      prevented = Dommy::Interaction::EventSynthesis.click(button)
      if !prevented && submit_button?(button) && (form = finder.form_for(button))
        form.dispatch_event(Dommy::Event.new("submit", "bubbles" => true, "cancelable" => true))
      end
      after_interaction
      button
    end

    # Click a link, firing its click event so SPA JS (Turbo, React Router, …)
    # can intercept. Real navigation on an un-prevented click is out of scope.
    def click_link(locator)
      link = finder.find_link(locator)
      Dommy::Interaction::EventSynthesis.click(link)
      after_interaction
      link
    end

    # Suppress strict-mode failure for JS errors raised inside the block (they
    # stay collected in #js_errors for inspection). For tests that expect errors.
    def allow_js_errors
      prev = @allow_errors
      @allow_errors = true
      yield
    ensure
      @allow_errors = prev
      @acknowledged = @js_errors.length
    end

    def dispose
      return if @disposed

      @disposed = true
      pending = unacknowledged
      @runtime&.dispose
      raise JsError, pending if @strict && !pending.empty?
    end

    private

    def unacknowledged = @js_errors[@acknowledged..] || []

    def submit_button?(button)
      if button.tag_name == "BUTTON"
        button.type == "submit"
      else
        %w[submit image].include?(button.type)
      end
    end

    # In strict mode, fail on any JS error collected since the last
    # acknowledgement. Marks all current errors acknowledged so each is reported
    # at most once.
    def check_js_errors!
      return if @allow_errors
      return unless @strict

      pending = unacknowledged
      return if pending.empty?

      @acknowledged = @js_errors.length
      raise JsError, pending
    end
  end
end
