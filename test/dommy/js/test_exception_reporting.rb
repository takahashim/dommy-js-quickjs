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

  # --- What the page is handed as event.error ---

  # A handler reads `.message` / `.stack` off the error before deciding what to
  # do, so those have to be there: one that throws while reading them never
  # reaches its own preventDefault, and the report it meant to cancel stands.
  def test_a_script_error_reaches_the_page_as_a_real_error
    html = <<~HTML
      <html><body>
        <script>
          window.__seen = null;
          window.addEventListener("error", function (e) {
            window.__seen = {
              isError: e.error instanceof Error,
              name: e.error.name,
              message: e.error.message,
              hasStack: typeof e.error.stack === "string" && e.error.stack.length > 0
            };
            e.preventDefault();
          });
        </script>
        <script>throw new TypeError("from the script");</script>
      </body></html>
    HTML
    # strict: true — the handler cancels, so nothing is left to fail on. That
    # only holds if reading the error did not throw first.
    browser = Dommy::Browser.new(html, strict: true)
    seen = browser.evaluate("window.__seen")

    assert seen["isError"], "the page gets an Error, not an opaque husk"
    assert_equal "TypeError", seen["name"]
    assert_equal "from the script", seen["message"]
    assert seen["hasStack"]
    assert_empty browser.js_errors, "the page handled it, so the host never hears"
  ensure
    browser&.dispose
  end

  # The engine discards the thrown value before the host hears about it, so the
  # Error the page gets is an equivalent rebuilt in the realm. Everything it can
  # observe matches; comparing identity is the one thing it cannot do.
  def test_a_rebuilt_error_is_not_the_identical_object
    html = <<~HTML
      <html><body>
        <script>
          window.__same = null;
          window.__thrown = new Error("mine");
          window.addEventListener("error", function (e) { window.__same = (e.error === window.__thrown); });
        </script>
        <script>throw window.__thrown;</script>
      </body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false)

    refute browser.evaluate("window.__same")
  ensure
    browser&.dispose
  end

  # Rebuilding must not run the event loop: a due-now timer from an earlier
  # script would fire before the next one, which no browser does.
  def test_rebuilding_does_not_disturb_script_order
    # The order is recorded in the DOM rather than a JS global, because reading
    # it back with `evaluate` would itself drive the loop and fire the timer.
    html = <<~HTML
      <html><head><title></title></head><body>
        <script>
          window.note = function (s) { document.title += (document.title ? "," : "") + s; };
          setTimeout(function () { note("timer"); }, 0);
        </script>
        <script>note("threw"); throw new Error("boom");</script>
        <script>note("next script");</script>
      </body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false, settle: false)

    assert_equal "threw,next script", browser.document.title,
      "the timer is still pending when the last script runs"
  ensure
    browser&.dispose
  end

  def test_the_host_still_logs_the_engine_exception
    html = '<html><body><script>throw new TypeError("for the log");</script></body></html>'
    browser = Dommy::Browser.new(html, strict: false)

    assert(browser.js_errors.any? { |e| e.message.to_s.include?("for the log") },
      "rebuilding is for the page; the host keeps the engine's own exception")
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

  # --- Promise rejection tracking, end to end ---
  #
  # These need the engine\'s JS rejection hook: without it the engine converts
  # the rejection to a host exception before anyone sees it, so the promise and
  # the reason are gone and `rejectionhandled` never happens at all.

  def skip_without_hook
    return if Dommy::Js::Quickjs::Backend.new.respond_to?(:promise_rejection_hook=)

    skip "needs the engine\'s promise_rejection_hook"
  end

  REJECTION_PAGE = <<~HTML
    <html><body><script>
      window.seen = {};
      window.addEventListener("unhandledrejection", function (e) {
        window.seen.unhandled = {
          isError: e.reason instanceof Error,
          name: e.reason && e.reason.name,
          message: e.reason && e.reason.message,
          samePromise: e.promise === window.p
        };
      });
      window.addEventListener("rejectionhandled", function (e) {
        window.seen.handled = {
          samePromise: e.promise === window.p,
          message: e.reason && e.reason.message,
          cancelable: e.cancelable
        };
      });
    </script></body></html>
  HTML

  def test_the_page_gets_the_reason_it_threw_and_the_promise
    skip_without_hook
    browser = Dommy::Browser.new(REJECTION_PAGE, strict: false)
    browser.execute('window.p = Promise.reject(new TypeError("the real reason"));')
    browser.settle
    seen = browser.evaluate("window.seen.unhandled")

    assert seen["isError"], "the reason is the Error the page threw"
    assert_equal "TypeError", seen["name"]
    assert_equal "the real reason", seen["message"]
    assert seen["samePromise"], "event.promise is the promise that rejected"
  ensure
    browser&.dispose
  end

  def test_rejectionhandled_fires_when_a_handler_arrives_late
    skip_without_hook
    browser = Dommy::Browser.new(REJECTION_PAGE, strict: false)
    browser.execute('window.p = Promise.reject(new TypeError("the real reason"));')
    browser.settle
    browser.execute("window.p.catch(function () {});")
    browser.settle
    seen = browser.evaluate("window.seen.handled")

    refute_nil seen
    assert seen["samePromise"]
    assert_equal "the real reason", seen["message"]
    refute seen["cancelable"], "the page is being informed, not consulted"
  ensure
    browser&.dispose
  end

  # A handler attached in a later task, with no checkpoint of ours in between:
  # the report is taken back, so nothing fails.
  def test_a_late_handler_retracts_the_report
    skip_without_hook
    html = <<~HTML
      <html><body><script>
        window.p = Promise.reject(new Error("retried"));
        setTimeout(function () { window.p.catch(function () {}); }, 10);
      </script></body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: false, settle: false)
    browser.advance_time(50)

    assert_empty browser.error_log.pending,
      "the page recovered, so the report is withdrawn"
    refute_empty browser.js_errors, "the console still shows it happened"
  ensure
    browser&.dispose
  end

  def test_a_rejection_nobody_handles_still_fails
    skip_without_hook
    browser = Dommy::Browser.new("<html><body></body></html>", strict: true)

    # `execute` drains the microtask queue, which ends the checkpoint the engine
    # decides at, so the failure lands on the line that caused it.
    error = assert_raises(Dommy::JsError) do
      browser.execute('Promise.reject(new Error("nobody catches this"));')
    end
    assert_includes error.message, "nobody catches this"
  ensure
    begin
      browser&.dispose
    rescue Dommy::JsError
      nil
    end
  end

  def test_a_rejection_is_reported_once
    skip_without_hook
    browser = Dommy::Browser.new("<html><body></body></html>", strict: false)
    browser.execute('Promise.reject(new Error("only once"));')
    browser.settle

    assert_equal 1, browser.js_errors.count { |e| e.message.to_s.include?("only once") },
      "the JS hook supersedes the Ruby relay; both would report the same rejection"
  ensure
    browser&.dispose
  end

  def test_the_host_log_names_the_kind_of_error
    skip_without_hook
    browser = Dommy::Browser.new("<html><body></body></html>", strict: false)
    browser.execute('Promise.reject(new TypeError("named"));')
    browser.settle

    assert(browser.js_errors.any? { |e| e.message.to_s.include?("TypeError: named") })
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

  # --- The completion value is not the page's business ---

  # A browser throws a classic script's completion value away. The gem converts
  # it, and refuses a pending Promise, so a script ending in the idiom that
  # publishes one for a later script used to reach the page as an uncaught
  # error — and a testharness page that saw it reported no results at all.
  def test_a_script_ending_in_a_promise_is_not_an_error
    html = <<~HTML
      <html><body>
        <script>
          var declared = "global";
          window.ready = new Promise(function (resolve) { window.resolveReady = resolve; });
        </script>
        <script>window.secondRan = typeof window.ready;</script>
      </body></html>
    HTML
    browser = Dommy::Browser.new(html, strict: true)

    assert_equal "object", browser.evaluate("window.secondRan"),
      "the next script still runs, and sees the promise"
    assert_equal "global", browser.evaluate("window.declared"),
      "a <script> declares in global scope; discarding the completion value must not change that"
    assert_empty browser.js_errors
  ensure
    browser&.dispose
  end

  # The same for an external script, which takes the compile-to-bytecode path.
  def test_a_cached_script_ending_in_a_promise_is_not_an_error
    win = Dommy.parse("<html><body></body></html>")
    rt = Dommy::Js::Quickjs::Runtime.new
    rt.install_window(win)
    rt.install_browser_globals
    rt.load_script_cached("window.later = new Promise(function (r) { window.go = r; });",
      cache_key: "http://example.test/completion-value.js")

    assert_equal "object", rt.evaluate("typeof window.later")
  ensure
    rt&.dispose
  end

  # An exception the HOST raised while evaluating carries Ruby frames. The page
  # can read `error.stack`, so those paths would be published to it; an empty
  # stack beats naming this gem's files, and beats a plausible-looking lie about
  # where the page failed.
  def test_a_host_error_does_not_hand_the_page_ruby_frames
    win = Dommy.parse("<html><body></body></html>")
    rt = Dommy::Js::Quickjs::Runtime.new
    rt.install_window(win)
    rt.install_browser_globals

    host = ::Quickjs::RuntimeError.new("raised by the host", nil)
    host.set_backtrace([
      "/Users/someone/lib/dommy/js/quickjs/backend.rb:82:in 'Quickjs::VM#eval_code'",
      "/Users/someone/lib/dommy/js/quickjs/runtime.rb:133:in 'Runtime#load_script'"
    ])
    assert_equal "", rt.send(:js_frames, host),
      "nothing here happened in JS, so the page is told nothing about where"
    refute_nil rt.send(:rebuild_error, host), "it still gets a usable Error"

    from_js = ::Quickjs::TypeError.new("thrown by the page", nil)
    from_js.set_backtrace(["    at f (<code>:1:34)", "    at <eval> (<code>:2:2)"])
    assert_equal "    at f (<code>:1:34)\n    at <eval> (<code>:2:2)", rt.send(:js_frames, from_js),
      "engine frames are the page's own, and stay"
  ensure
    rt&.dispose
  end
end
