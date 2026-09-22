# frozen_string_literal: true

require "test_helper"

# dommy-rack isn't published yet, so it's only on the load path inside the
# dommy monorepo. In a standalone clone (e.g. CI), skip this file rather than
# aborting the whole suite at load time.
begin
  require "dommy/js/quickjs/rack"
rescue LoadError
  warn "skipping test_session_strict_js_errors.rb: dommy-rack not available"
  return
end

# Dommy::Rack::Session.new(app, strict_js_errors: true) — the session fails at
# the next checkpoint on JavaScript the page left unhandled, so the failure
# lands on the line that caused it rather than at teardown.
class Dommy::Js::TestSessionStrictJsErrors < Minitest::Test
  PAGES = {
    "/boots-badly" => '<html><body><script>throw new Error("boot failed");</script></body></html>',
    "/clean" => "<html><body><p>fine</p></body></html>",
    "/handles-its-own" => <<~HTML,
      <html><body>
        <script>window.addEventListener("error", function (e) { e.preventDefault(); });</script>
        <script>throw new Error("the page handled this");</script>
      </body></html>
    HTML
    "/throws-on-a-timer" => <<~HTML,
      <html><body><script>
        setTimeout(function () { throw new Error("from the timer"); }, 50);
      </script></body></html>
    HTML
  }.freeze

  APP = lambda do |env|
    body = PAGES[env["PATH_INFO"]]
    return [404, {"content-type" => "text/plain"}, ["nope"]] unless body

    [200, {"content-type" => "text/html"}, [body]]
  end

  def session(strict: true)
    ::Dommy::Rack::Session.new(APP, javascript: true, strict_js_errors: strict)
  end

  def test_a_boot_error_fails_the_visit
    s = session
    error = assert_raises(Dommy::JsError) { s.visit("/boots-badly") }

    assert_includes error.message, "boot failed"
    assert_includes error.message, "/boots-badly", "the message names where the page was"
  ensure
    s&.dispose rescue nil # rubocop:disable Style/RescueModifier
  end

  def test_a_page_that_handles_its_own_errors_passes
    s = session
    s.visit("/handles-its-own")

    assert_empty s.js_errors
    s.dispose
  end

  def test_a_timer_error_fails_at_advance_time
    s = session
    s.visit("/throws-on-a-timer")
    error = assert_raises(Dommy::JsError) { s.advance_time(100) }

    assert_includes error.message, "from the timer"
  ensure
    s&.dispose rescue nil # rubocop:disable Style/RescueModifier
  end

  def test_each_error_is_reported_once
    s = session
    assert_raises(Dommy::JsError) { s.visit("/boots-badly") }

    s.settle # the queue drained, so the next checkpoint is quiet
    s.dispose
  end

  # The regression the ledger's history / pending split exists for. Navigating
  # clears the console, and the old index-based bookkeeping then pointed past
  # the end of a shorter list, so an unreported error from the page that just
  # went away silently read as "none".
  def test_an_unreported_error_survives_the_navigation_that_clears_the_console
    s = session(strict: false)
    s.visit("/boots-badly")
    refute_empty s.js_errors
    s.__internal_js_runtime.error_log.strict = true

    error = assert_raises(Dommy::JsError) { s.visit("/clean") }
    assert_includes error.message, "boot failed"
    assert_empty s.js_errors, "the console still cleared; only the queue survived"
  ensure
    s&.dispose rescue nil # rubocop:disable Style/RescueModifier
  end

  def test_the_console_still_clears_on_navigation
    s = session(strict: false)
    s.visit("/boots-badly")
    refute_empty s.js_errors
    s.visit("/clean")

    assert_empty s.js_errors, "a browser's console clears when the page changes"
  ensure
    s&.dispose rescue nil # rubocop:disable Style/RescueModifier
  end

  def test_allow_js_errors_suppresses_the_failure
    s = session
    s.allow_js_errors { s.visit("/boots-badly") }

    assert(s.js_errors.any? { |e| e.message.to_s.include?("boot failed") },
      "still inspectable afterwards")
    s.dispose
  end

  def test_without_strict_mode_errors_are_only_recorded
    s = session(strict: false)
    s.visit("/boots-badly")

    assert(s.js_errors.any? { |e| e.message.to_s.include?("boot failed") })
    s.dispose
  end

  def test_dispose_fails_on_what_the_last_step_produced
    s = session(strict: false)
    s.visit("/boots-badly")
    s.__internal_js_runtime.error_log.strict = true

    assert_raises(Dommy::JsError) { s.dispose }
  end
end
