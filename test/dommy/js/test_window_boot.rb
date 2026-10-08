# frozen_string_literal: true

require "test_helper"

# Opening a window is paid on every page load, so what it costs is pinned
# here, next to what it must still deliver. The ~200 interface globals are
# seeded lazily (each prototype is built when first read), their statics
# arrive in one crossing, and a bootstrap bundle's completion value is not
# handed to Ruby (window_builtins.js ends on `window.globalThis = globalThis`,
# which used to marshal the whole global object).
class Dommy::Js::TestWindowBoot < Minitest::Test
  def setup
    @win = Dommy.parse("<!DOCTYPE html><html><body><p>x</p></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.define_host_object("document", @win.document)
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  def test_lazily_seeded_interfaces_resolve_like_eager_ones
    result = @rt.evaluate(<<~JS)
      [typeof HTMLTableCaptionElement,
       Object.getPrototypeOf(HTMLTableCaptionElement.prototype) === HTMLElement.prototype,
       document.querySelector("p") instanceof HTMLParagraphElement,
       document.querySelector("p") instanceof Node,
       window.Range === Range,
       document.defaultView.DOMException === DOMException].join(",")
    JS
    assert_equal "function,true,true,true,true,true", result
  end

  def test_an_interface_built_after_the_window_still_gets_its_statics
    assert_equal "function,function", @rt.evaluate("[typeof URL.parse, typeof URL.createObjectURL].join(',')")
  end

  def test_legacy_factory_functions_share_the_lazy_prototype
    assert_equal "true,true", @rt.evaluate(<<~JS)
      [new Image() instanceof HTMLImageElement, Option.prototype === HTMLOptionElement.prototype].join(",")
    JS
  end

  def test_assigning_a_global_before_it_is_built_replaces_it
    assert_equal 1, @rt.evaluate(<<~JS)
      globalThis.HTMLMarqueeElement = 1;
      return HTMLMarqueeElement;
    JS
  end

  def test_opening_a_window_crosses_into_ruby_a_bounded_number_of_times
    previous = ENV.fetch("DOMMY_JS_BRIDGE_PROFILE", nil)
    ENV["DOMMY_JS_BRIDGE_PROFILE"] = "1"
    rt = Dommy::Js::Quickjs::Runtime.new
    profile = rt.instance_variable_get(:@bridge).instance_variable_get(:@profile)
    win = Dommy.parse("<!DOCTYPE html><p>x</p>")
    rt.define_host_object("document", win.document)
    rt.install_window(win)
    window_crossings = crossings(profile)
    profile.reset
    rt.install_browser_globals
    globals_crossings = crossings(profile)

    # It was 424 (one host read and one statics lookup per interface) and
    # 211 (the global object marshalled back to Ruby).
    assert_operator window_crossings, :<, 60
    assert_operator globals_crossings, :<, 80
  ensure
    rt&.dispose
    previous ? ENV["DOMMY_JS_BRIDGE_PROFILE"] = previous : ENV.delete("DOMMY_JS_BRIDGE_PROFILE")
  end

  private

  def crossings(profile) = profile.snapshot.sum { |_, counts| counts["__total__"].to_i }
end
