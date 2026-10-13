# frozen_string_literal: true

require "test_helper"

# QuickJS hands a lone surrogate to Ruby as WTF-8 bytes, while dommy's
# dehydrate scrubs one in a value to U+FFFD. A page-chosen property name
# (`storage[k]`) must take the same scrub as the same string passed as an
# argument (`storage.setItem(k, …)`), or the two reach the host as different
# keys.
class Dommy::Js::TestLoneSurrogateNames < Minitest::Test
  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  def test_a_named_write_reads_back_through_get_item
    @rt.execute('localStorage.clear(); localStorage["a\\uD800"] = "v";')
    assert_equal "v", @rt.evaluate('localStorage.getItem("a\\uD800")')
  end

  def test_a_set_item_reads_back_through_a_named_read
    @rt.execute('sessionStorage.clear(); sessionStorage.setItem("\\uDC00b", "v");')
    assert_equal "v", @rt.evaluate('sessionStorage["\\uDC00b"]')
  end

  def test_a_named_delete_removes_the_set_item_key
    @rt.execute('localStorage.clear(); localStorage.setItem("\\uD800", "v"); delete localStorage["\\uD800"];')
    assert_nil @rt.evaluate('localStorage.getItem("\\uD800")')
  end

  def test_a_named_key_is_found_by_in
    @rt.execute('localStorage.clear(); localStorage.setItem("\\uD800", "v");')
    assert_equal true, @rt.evaluate('"\\uD800" in localStorage')
  end

  # The known departure: a browser keeps a DOMString's lone surrogates, so
  # these are three keys there and one here, and the written key and value
  # read back as U+FFFD.
  def test_lone_surrogates_reach_the_host_as_u_fffd
    @rt.execute(<<~JS)
      localStorage.clear();
      localStorage["\\uD800"] = "a";
      localStorage["\\uDC00"] = "\\uDBFF";
      localStorage.setItem("\\uFFFD", localStorage.getItem("\\uFFFD") + "c");
    JS
    assert_equal ["�"], @rt.evaluate("Object.keys(localStorage)").to_a
    assert_equal "�c", @rt.evaluate('localStorage["\\uD800"]')
  end
end
