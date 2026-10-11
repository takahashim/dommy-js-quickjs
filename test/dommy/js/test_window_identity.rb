# frozen_string_literal: true

require "test_helper"

# The window and the global object are two objects here: QuickJS makes the
# global, and the window is a proxy for the Ruby Window. They share names (a
# global is readable off the window and back), but not identity, and the line
# between them is one rule: `globalThis` (with the engine's top-level `this`)
# is the JS global, and every Web API that hands out a window hands out the
# window proxy.
class Dommy::Js::TestWindowIdentity < Minitest::Test
  def setup
    @h = Dommy::Js::BrowserHarness.new("<!DOCTYPE html><html><body><iframe id='f'></iframe></body></html>")
  end

  def teardown
    @h&.dispose
  end

  def test_every_name_for_the_window_is_the_window
    assert_equal(
      { "self" => true, "top" => true, "parent" => true, "frames" => true,
        "window.self" => true, "window.top" => true, "window.parent" => true, "window.frames" => true,
        "document.defaultView" => true },
      @h.evaluate(<<~JS),
        ({
          self: self === window, top: top === window, parent: parent === window, frames: frames === window,
          "window.self": window.self === self, "window.top": window.top === top,
          "window.parent": window.parent === parent, "window.frames": window.frames === frames,
          "document.defaultView": document.defaultView === self,
        })
      JS
    )
  end

  def test_a_frame_names_the_top_window_as_the_window
    assert_equal([true, true], @h.evaluate(<<~JS))
      (() => {
        const w = document.getElementById("f").contentWindow;
        return [w.parent === self, w.top === top];
      })()
    JS
  end

  # The one difference left: the global object is not the window.
  def test_the_global_object_is_not_the_window
    assert_equal([false, false], @h.evaluate("[globalThis === window, globalThis === self]"))
  end

  # A global the page made is the window's property of that name, so reading,
  # rewriting and testing for it through the window (testharness.js goes
  # through `self`) stays in JS.
  def test_a_page_global_reached_through_the_window_does_not_cross_into_ruby
    previous = ENV.fetch("DOMMY_JS_BRIDGE_PROFILE", nil)
    ENV["DOMMY_JS_BRIDGE_PROFILE"] = "1"
    h = Dommy::Js::BrowserHarness.new
    h.runtime.load_script("var lib = { n: 0 }; function helper() {}")
    h.runtime.reset_bridge_crossing_counts
    assert_equal(true, h.evaluate(<<~JS))
      (() => {
        for (let i = 0; i < 100; i++) { self.lib.n++; window.helper(); }
        self.lib = { n: 100 }; window.helper = function () {};
        return "lib" in self && "helper" in window && lib.n === 100;
      })()
    JS
    assert_equal(0, h.runtime.bridge_crossing_counts.sum { |_, counts| counts["__total__"].to_i })
  ensure
    h&.dispose
    previous ? ENV["DOMMY_JS_BRIDGE_PROFILE"] = previous : ENV.delete("DOMMY_JS_BRIDGE_PROFILE")
  end

  # self, parent and frames are [Replaceable]: an assignment replaces the
  # global with the value. top is [LegacyUnforgeable] and keeps the window.
  def test_self_parent_and_frames_are_replaceable_and_top_is_not
    assert_equal([1, 2, 3, true], @h.evaluate(<<~JS))
      (() => {
        self = 1; parent = 2; frames = 3; top = 4;
        return [self, parent, frames, top === window];
      })()
    JS
  end
end
