# frozen_string_literal: true

require "test_helper"

# The harness itself: it must surface swallowed rejections (with JS stacks) and
# console output, drive deferred work, and serve a fetch stub — the diagnostics
# that make framework bring-up tractable.
class Dommy::Js::TestBrowserHarness < Minitest::Test
  def setup
    @h = Dommy::Js::BrowserHarness.new("<div id='root'></div>")
  end

  def teardown
    @h&.dispose
  end

  # A rejection with no .catch is captured, with the JS stack in #backtrace.
  def test_captures_swallowed_rejection_with_backtrace
    @h.execute("function boom() { Promise.reject(new TypeError('kaboom')); } boom();")
    @h.pump
    err = @h.errors.find { |e| e.message.include?("kaboom") }
    refute_nil err, "expected the swallowed rejection to be captured"
    assert_kind_of Quickjs::TypeError, err
    assert(Array(err.backtrace).any? { |line| line.include?("boom") }, "expected a JS stack frame")
  end

  # console.* output is captured.
  def test_captures_console
    @h.execute('console.warn("hi", 42);')
    log = @h.logs.find { |l| l.to_s.include?("hi") }
    refute_nil log
    assert_equal :warning, log.severity
  end

  # The fetch stub is served through window.fetch.
  def test_fetch_stub
    @h.stub_fetch("/ping" => { "status" => 200, "body" => "pong", "contentType" => "text/plain" })
    @h.execute('(async () => { const r = await fetch("/ping"); globalThis.__b = await r.text(); })();')
    @h.pump
    assert_equal "pong", @h.evaluate("globalThis.__b")
  end

  # Browser bare-globals are wired (install_browser_globals).
  def test_browser_globals_installed
    assert_equal true, @h.evaluate("self === globalThis")
    assert_equal "function", @h.evaluate("typeof fetch")
    assert_equal "function", @h.evaluate("typeof CSS.escape")
    assert_equal "http://localhost/", @h.evaluate("location.href")
  end
end
