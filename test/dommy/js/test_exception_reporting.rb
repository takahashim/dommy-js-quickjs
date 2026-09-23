# frozen_string_literal: true

require "test_helper"

# WHATWG "report an exception" driven through a real JS engine: every uncaught
# error the page produces fires a cancelable `error` event at the window first,
# and only an UNHANDLED one reaches the host's error log (the browser's
# "may report the error to a developer console" step).
#
# The core suite covers the algorithm itself with Ruby callbacks; this covers the
# entry points that need a JS engine — a throwing <script>, a throwing timer
# callback, and a rejected promise.
class Dommy::Js::TestExceptionReporting < Minitest::Test
  # --- A throwing <script> ---

  def test_a_throwing_script_fires_window_onerror
    html = <<~HTML
      <html><body>
        <script>
          window.__seen = [];
          window.onerror = function (message, filename, lineno, colno, error) {
            window.__seen.push({ message: message, hasError: !!error });
          };
        </script>
        <script>throw new Error("from the script");</script>
      </body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)
    seen = browser.evaluate("window.__seen")

    assert_equal 1, seen.length, "a script whose evaluation throws reaches window.onerror"
    assert_includes seen[0]["message"], "from the script"
    assert seen[0]["hasError"], "the report carries the thrown value as event.error"
  ensure
    browser&.dispose
  end

  def test_a_script_the_page_handles_does_not_fail_the_test
    html = <<~HTML
      <html><body>
        <script>window.addEventListener("error", function (e) { e.preventDefault(); });</script>
        <script>throw new Error("handled by the page");</script>
      </body></html>
    HTML
    # strict: true — the page cancels the report, so nothing is left to fail on.
    browser = Dommy::Browser.new(html, strict: true)

    assert_empty browser.js_errors,
      "a page with its own error handling suppresses the failure, as in a browser"
  ensure
    browser&.dispose
  end

  def test_an_unhandled_script_error_still_fails_strict_mode
    html = '<html><body><script>throw new Error("unhandled");</script></body></html>'
    error = assert_raises(Dommy::JsError) { Dommy::Browser.new(html, strict: true) }

    assert_includes error.message, "unhandled"
  end

  def test_a_throwing_script_does_not_stop_the_next_script
    html = <<~HTML
      <html><body>
        <script>window.__ran = [];</script>
        <script>window.__ran.push("first"); throw new Error("boom");</script>
        <script>window.__ran.push("second");</script>
      </body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)

    assert_equal %w[first second], browser.evaluate("window.__ran"),
      "an exception unwinds to the script boundary, not to the whole page"
  ensure
    browser&.dispose
  end

  # --- A throwing timer callback ---

  def test_a_throwing_timer_callback_is_reported_at_the_window
    html = <<~HTML
      <html><body><script>
        window.__seen = [];
        window.onerror = function (message) { window.__seen.push(message); };
        setTimeout(function () { throw new Error("from the timer"); }, 10);
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)
    browser.advance_time(20)

    assert(browser.evaluate("window.__seen").any? { |m| m.to_s.include?("from the timer") },
      "a timer callback's exception is reported, and the event loop keeps running")
  ensure
    browser&.dispose
  end

  def test_a_handled_timer_error_does_not_reach_the_host
    html = <<~HTML
      <html><body><script>
        window.addEventListener("error", function (e) { e.preventDefault(); });
        setTimeout(function () { throw new Error("swallowed"); }, 10);
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)
    browser.advance_time(20)

    refute(browser.js_errors.any? { |e| e.message.to_s.include?("swallowed") },
      "the page canceled the report, so the host never logs it")
  ensure
    browser&.dispose
  end

  # --- An unhandled rejection ---

  # The page gets the event, and the host gets the message. `event.reason` is a
  # stand-in rather than the page's own Error: the engine hands the host a
  # converted Ruby exception, not the rejected JS value, so its identity (and
  # with it `.message` / `.stack`) does not survive the crossing. Same missing
  # signal that keeps `rejectionhandled` unimplemented.
  def test_an_unhandled_rejection_fires_the_unhandledrejection_event
    html = <<~HTML
      <html><body><script>
        window.__seen = [];
        window.addEventListener("unhandledrejection", function (e) {
          window.__seen.push({ type: e.type, hasReason: e.reason != null });
        });
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)
    browser.execute('Promise.reject(new Error("rejected"));')
    browser.settle

    seen = browser.evaluate("window.__seen")
    assert_equal 1, seen.length, "the page sees unhandledrejection, not just the host"
    assert_equal "unhandledrejection", seen[0]["type"]
    assert seen[0]["hasReason"]
    assert(browser.js_errors.any? { |e| e.message.to_s.include?("rejected") },
      "the host log keeps the reason's message")
  ensure
    browser&.dispose
  end

  def test_a_canceled_rejection_does_not_fail_strict_mode
    html = <<~HTML
      <html><body><script>
        window.addEventListener("unhandledrejection", function (e) { e.preventDefault(); });
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: true)
    browser.execute('Promise.reject(new Error("handled rejection"));')
    browser.settle

    assert_empty browser.js_errors,
      "preventDefault on unhandledrejection suppresses it, as in a browser"
  ensure
    browser&.dispose
  end

  # --- Where the error happened ---

  def test_an_external_script_reports_its_own_url_and_position
    resources = Dommy::Resources.static(
      "/reports-position.js" => {"content_type" => "application/javascript",
                    "body" => "function inner() { throw new Error('deep') }\ninner();"}
    )
    html = <<~HTML
      <html><body>
        <script>window.__at = null; window.onerror = function (m, f, l, c) { window.__at = [f, l, c]; };</script>
        <script src="/reports-position.js"></script>
      </body></html>
    HTML
    browser = Dommy::Browser.new(html, url: "http://example.test/", resources: resources, strict: false)
    file, line, column = browser.evaluate("window.__at")

    assert_equal "http://example.test/reports-position.js", file
    assert_equal 1, line
    assert_operator column, :>, 0
  ensure
    browser&.dispose
  end

  # A listener's throw crosses as an opaque JS value, so its frames have to
  # travel with the throw or the position is lost.
  def test_a_listener_error_reports_a_position
    html = <<~HTML
      <html><body><script>
        window.__at = null;
        window.onerror = function (m, f, l, c) { window.__at = [f, l, c]; };
        document.body.addEventListener("click", function () { throw new Error("listener"); });
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, url: "http://example.test/page", strict: false)
    browser.execute("document.body.click()")
    file, line, column = browser.evaluate("window.__at")

    assert_equal "http://example.test/page", file, "an inline script reports the document URL"
    assert_operator line, :>, 0
    assert_operator column, :>, 0
  ensure
    browser&.dispose
  end

  # --- A dynamically inserted script ---

  def test_a_script_that_downloaded_and_then_threw_still_fires_load
    resources = Dommy::Resources.static(
      "/threw-after-download.js" => {"content_type" => "application/javascript", "body" => "throw new Error('in the chunk');"}
    )
    browser = Dommy::Browser.new("<html><body></body></html>", resources: resources, strict: false)
    browser.execute(<<~JS)
      window.__ev = [];
      var s = document.createElement("script");
      s.src = "/threw-after-download.js";
      s.onload = function () { window.__ev.push("load"); };
      s.onerror = function () { window.__ev.push("error"); };
      document.head.appendChild(s);
    JS
    browser.settle

    assert_equal ["load"], browser.evaluate("window.__ev"),
      "the element's error event means the FETCH failed; this one downloaded fine"
    assert(browser.js_errors.any? { |e| e.message.to_s.include?("in the chunk") },
      "the evaluation's exception is still reported")
  ensure
    browser&.dispose
  end

  def test_a_script_that_failed_to_download_fires_error
    browser = Dommy::Browser.new("<html><body></body></html>",
      resources: Dommy::Resources.static({}), strict: false)
    browser.execute(<<~JS)
      window.__ev = [];
      var s = document.createElement("script");
      s.src = "/never-downloaded.js";
      s.onload = function () { window.__ev.push("load"); };
      s.onerror = function () { window.__ev.push("error"); };
      document.head.appendChild(s);
    JS
    browser.settle

    assert_equal ["error"], browser.evaluate("window.__ev")
  ensure
    browser&.dispose
  end

  # --- reportError ---

  def test_report_error_reaches_window_onerror_and_the_host
    html = <<~HTML
      <html><body><script>
        window.__seen = [];
        window.onerror = function (message) { window.__seen.push(message); };
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)
    browser.execute('reportError(new Error("programmatic"));')

    assert(browser.evaluate("window.__seen").any? { |m| m.to_s.include?("programmatic") },
      "self.reportError IS report-an-exception exposed to authors")
    assert(browser.js_errors.any? { |e| e.message.to_s.include?("programmatic") },
      "unhandled, so it also reaches the host")
  ensure
    browser&.dispose
  end
end
