# frozen_string_literal: true

require "test_helper"

# The bare window globals the browser environment installs (timer_globals.js,
# browser_globals.js) follow the IDL: their lengths and names are the
# operations', a timer hands its extra arguments to the handler, and values
# that change are read from the window rather than copied once at boot.
class Dommy::Js::TestBareWindowGlobals < Minitest::Test
  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  def test_timer_globals_have_the_idl_lengths
    lengths = @rt.evaluate(<<~JS)
      [setTimeout, clearTimeout, setInterval, clearInterval,
       requestAnimationFrame, cancelAnimationFrame, queueMicrotask].map((f) => `${f.name}:${f.length}`).join(",")
    JS
    assert_equal "setTimeout:1,clearTimeout:0,setInterval:1,clearInterval:0," \
                 "requestAnimationFrame:1,cancelAnimationFrame:1,queueMicrotask:1", lengths
  end

  # HTML "timer initialization steps": the arguments after the timeout are
  # passed to the handler.
  def test_set_timeout_hands_its_extra_arguments_to_the_handler
    @rt.execute(<<~JS)
      globalThis.SEEN = null;
      setTimeout((a, b) => { SEEN = [a, b].join("/"); }, 0, "x", 2);
    JS
    @rt.run_until_idle
    assert_equal "x/2", @rt.evaluate("SEEN")
  end

  def test_forwarded_window_methods_take_the_operation_name_and_length
    shapes = @rt.evaluate(<<~JS)
      [structuredClone, atob, fetch, addEventListener, getComputedStyle, alert]
        .map((f) => `${f.name}:${f.length}`).join(",")
    JS
    assert_equal "structuredClone:1,atob:1,fetch:1,addEventListener:2,getComputedStyle:1,alert:0", shapes
  end

  # innerWidth & co. are [Replaceable] attributes of the window: read live,
  # and an assignment replaces them.
  def test_changing_window_values_are_read_live_and_replaceable
    assert_equal true, @rt.evaluate("innerWidth === window.innerWidth")
    @rt.execute("innerWidth = 42")
    assert_equal 42, @rt.evaluate("innerWidth")
  end

  # The bare storage globals are the window's own Storage objects.
  def test_storage_globals_are_the_windows
    assert_equal true, @rt.evaluate("localStorage === window.localStorage && sessionStorage === window.sessionStorage")
    @rt.execute('localStorage.setItem("k", "v")')
    assert_equal "v", @rt.evaluate('window.localStorage.getItem("k")')
  end

  # An opaque origin has no storage: the getters throw a SecurityError
  # (HTML Web storage, the localStorage / sessionStorage getters, when
  # "obtain a storage bottle map" fails; Storage Standard, "obtain a storage
  # key" is failure for an opaque origin). The bare globals throw on read like
  # window's own, and installing the globals does not.
  def test_storage_globals_throw_on_an_opaque_origin_only_when_read
    win = Dommy.parse("<html><body></body></html>")
    win.location.__internal_set_url__("about:blank")
    rt = Dommy::Js::Quickjs::Runtime.new
    rt.install_window(win)
    rt.install_browser_globals

    names = rt.evaluate(<<~JS)
      ["localStorage", "sessionStorage"].map((n) => {
        try { globalThis[n]; return n + ":no-throw"; }
        catch (e) { return n + ":" + e.name; }
      }).join(",")
    JS
    assert_equal "localStorage:SecurityError,sessionStorage:SecurityError", names
    assert_equal "function", rt.evaluate("typeof structuredClone"), "the rest of the globals are installed"
  ensure
    rt&.dispose
  end

  # A top-level window has no container, so the bare frameElement is null,
  # like window.frameElement.
  def test_bare_frame_element_reads_the_window
    assert_equal true, @rt.evaluate("frameElement === null && frameElement === window.frameElement")
  end

end
