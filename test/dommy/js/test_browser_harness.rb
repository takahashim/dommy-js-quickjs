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

  # In a browser the window IS the global object, so a global attached either
  # way is visible — same identity — from both views. UMD bundles attach to
  # whichever of globalThis/window/this they detect first (e.g. Stimulus to
  # globalThis), and app code then reads it off window.
  def test_window_and_global_this_share_globals
    # globalThis -> window (the Stimulus UMD case).
    @h.execute("globalThis.Stimulus = { app: 1 };")
    assert_equal true, @h.evaluate("window.Stimulus === globalThis.Stimulus")
    assert_equal true, @h.evaluate('"Stimulus" in window')

    # window -> globalThis (and a bare read).
    @h.execute("window.Widget = { v: 2 };")
    assert_equal true, @h.evaluate("globalThis.Widget === window.Widget")
    assert_equal 2, @h.evaluate("Widget.v")

    # A top-level `var` in a script loaded like a <script> (UMD global build).
    @h.runtime.load_script("var Library = { ok: true };")
    assert_equal true, @h.evaluate("window.Library === globalThis.Library")

    # delete through the window drops the global.
    @h.execute("delete window.Stimulus;")
    assert_equal "undefined", @h.evaluate("typeof globalThis.Stimulus")

    # Host-resolved window properties are NOT shadowed by the fallback.
    assert_equal true, @h.evaluate("window.document === document")
    assert_equal true, @h.evaluate("window.location === location")
  end
end
