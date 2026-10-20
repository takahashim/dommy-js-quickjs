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

  # The window's own properties include the globals the page made, so walking
  # the window's keys (a leak check over `Object.keys(self)`) finds them, and
  # one deleted through the window is gone from the keys too.
  def test_the_window_lists_the_page_globals_among_its_own_keys
    @h.runtime.load_script("var pageVar = 1; function pageFn() {}")
    assert_equal([true, true, true, false], @h.evaluate(<<~JS))
      (() => {
        const forIn = []; for (const k in self) forIn.push(k);
        globalThis.gone = 1; delete window.gone;
        return [Object.keys(self).includes("pageVar"), Object.keys(window).includes("pageFn"),
                forIn.includes("pageVar"), Object.keys(self).includes("gone")];
      })()
    JS
  end

  # A property defined on the window is a global: the bare name resolves to it.
  def test_a_property_defined_on_the_window_is_a_global
    assert_equal([1, 1, 2, 3, true], @h.evaluate(<<~JS))
      (() => {
        Object.defineProperty(self, "definedValue", { value: 1, configurable: true });
        Object.defineProperty(window, "definedGetter", { get() { return 2; }, configurable: true });
        Object.defineProperty(window, "definedConstant", { value: 3 });
        return [definedValue, self.definedValue, definedGetter, definedConstant,
                Object.getOwnPropertyDescriptor(window, "definedConstant").configurable === false];
      })()
    JS
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

  # window and document are [LegacyUnforgeable], and history, navigator,
  # crypto, indexedDB and caches plain readonly attributes: assigning the bare
  # name keeps the window's object (a strict-mode script gets a TypeError).
  # performance and screen are [Replaceable], so an assignment replaces them.
  def test_the_window_readonly_attributes_ignore_an_assignment
    names = %w[window document history navigator crypto]
    assert_equal(names.to_h { |n| [n, true] }.merge("strict" => "TypeError", "performance" => 1, "screen" => 2),
                 @h.evaluate(<<~JS))
      (() => {
        const result = {};
        for (const name of #{names.to_json}) {
          const before = globalThis[name];
          (0, eval)(name + " = 1");
          result[name] = globalThis[name] === before;
        }
        try { (0, eval)("'use strict'; document = 1"); result.strict = "no error"; } catch (e) { result.strict = e.name; }
        (0, eval)("performance = 1; screen = 2");
        result.performance = performance; result.screen = screen;
        return result;
      })()
    JS
  end

  # A readonly attribute the window has no object for (dommy implements
  # neither indexedDB nor caches) is no global, so feature detection sees it
  # missing and a page's polyfill takes its place.
  def test_a_missing_window_object_is_left_for_a_polyfill
    assert_equal([false, false, "fake", "fake"], @h.evaluate(<<~JS))
      (() => {
        const missing = ["indexedDB" in globalThis, "caches" in globalThis];
        (0, eval)("'use strict'; globalThis.indexedDB = 'fake'; globalThis.caches = 'fake'");
        return [...missing, indexedDB, caches];
      })()
    JS
  end

  # Interface objects are not enumerable properties of the global (WebIDL).
  def test_interface_objects_are_not_enumerable_globals
    assert_equal([false, false, false, false, []], @h.evaluate(<<~JS))
      (() => {
        Node; // built
        const keys = Object.keys(globalThis);
        return [keys.includes("Node"), keys.includes("HTMLDivElement"), keys.includes("Image"),
                Object.prototype.propertyIsEnumerable.call(globalThis, "Node"),
                ["CustomStateSet", "Observable", "Subscriber"].filter((name) => keys.includes(name))];
      })()
    JS
  end

  # self, parent and frames are [Replaceable]: an assignment replaces the
  # global with the value. top is [LegacyUnforgeable] and keeps the window.
  def test_self_parent_and_frames_are_replaceable_and_top_is_not
    assert_equal([1, 2, 3, true, "TypeError"], @h.evaluate(<<~JS))
      (() => {
        self = 1; parent = 2; frames = 3; top = 4;
        let strict;
        try { (0, eval)("'use strict'; top = 5"); strict = "no error"; } catch (e) { strict = e.name; }
        return [self, parent, frames, top === window, strict];
      })()
    JS
  end

  # A Window member replaced through either name is replaced for both, as on a
  # real window, where the two are one object: a page wrapping window.fetch
  # sees its own bare fetch() calls, and a mock planted with defineProperty
  # answers window.matchMedia.
  def test_a_replaced_window_member_is_the_same_through_either_name
    assert_equal([true, true, true, true, "fake", "fake"], @h.evaluate(<<~JS))
      (() => {
        const f = () => "f";
        window.fetch = f;
        const g = () => 0;
        globalThis.setTimeout = g;
        Object.defineProperty(window, "matchMedia", { value: () => "fake", writable: true, configurable: true });
        return [fetch === f, window.fetch === f, setTimeout === g, window.setTimeout === g,
                matchMedia(), window.matchMedia()];
      })()
    JS
  end

  # One the page has not replaced still runs the window's.
  def test_an_unreplaced_window_member_runs_the_windows
    assert_equal(%w[hi hi], @h.evaluate('[atob("aGk="), window.atob("aGk=")]'))
  end

  # A global defined non-configurable through the window keeps one value
  # through every name, across assignments and a redefinition.
  def test_a_non_configurable_global_keeps_one_value
    assert_equal([[3, 3, 3], [5, 5]], @h.evaluate(<<~JS))
      (() => {
        Object.defineProperty(window, "pinned", { value: 1, writable: true });
        globalThis.pinned = 2;
        window.pinned = 3;
        const assigned = [pinned, window.pinned, globalThis.pinned];
        Object.defineProperty(window, "pinned", { value: 5 });
        return [assigned, [pinned, window.pinned]];
      })()
    JS
  end

  # An accessor defined on the window runs with the window as `this`.
  def test_an_accessor_defined_on_the_window_sees_the_window
    assert_equal(true, @h.evaluate(<<~JS))
      (() => {
        Object.defineProperty(window, "seenThis", { get() { return this === window; }, configurable: true });
        return window.seenThis;
      })()
    JS
  end

  # The window's own keys leave out the bridge's internal names, and a window
  # cannot be made non-extensible (HTML's WindowProxy [[PreventExtensions]]
  # returns false), so walking its keys keeps working.
  def test_the_window_keys_leave_out_the_bridge_and_the_window_stays_extensible
    assert_equal([false, true, "TypeError", false, true], @h.evaluate(<<~JS))
      (() => {
        let error = null;
        try { Object.preventExtensions(window); } catch (e) { error = e.constructor.name; }
        return [Object.getOwnPropertyNames(window).some((k) => k.startsWith("__rb")),
                Object.keys(window).includes("fetch"), error, Reflect.preventExtensions(window),
                Object.keys(window).length > 0];
      })()
    JS
  end

  # A global deleted through the window and made again under the bare name is
  # the window's again; a Window member deleted through the window stays gone.
  def test_a_deleted_global_made_again_is_the_windows
    assert_equal([[2, true, true], ["undefined", false]], @h.evaluate(<<~JS))
      (() => {
        window.remade = 1;
        delete window.remade;
        globalThis.remade = 2;
        const remade = [window.remade, "remade" in window, Object.keys(window).includes("remade")];
        delete window.Event;
        return [remade, [typeof window.Event, "Event" in window]];
      })()
    JS
  end

  # A Window member saved before the page wraps it — through the bare name,
  # globalThis or the window — is still the original, as a saved native
  # function is in a browser: calling it does not call the wrapper back.
  def test_a_saved_window_member_survives_a_wrapper_around_it
    assert_equal(%w[object number ok object object], @h.evaluate(<<~JS))
      (() => {
        const results = [];
        const savedFetch = fetch;
        window.fetch = (...args) => savedFetch(...args);
        results.push(typeof window.fetch("data:,x"));
        const savedSetTimeout = setTimeout;
        window.setTimeout = (callback, delay) => savedSetTimeout(callback, delay);
        results.push(typeof window.setTimeout(() => {}, 0));
        const savedAdd = addEventListener;
        window.addEventListener = function (...args) { return savedAdd.call(this, ...args); };
        window.addEventListener("x", () => {});
        results.push("ok");
        const fromGlobal = globalThis.fetch;
        globalThis.fetch = (...args) => fromGlobal(...args);
        results.push(typeof fetch("data:,x"));
        const fromWindow = window.fetch;
        window.fetch = (...args) => fromWindow(...args);
        results.push(typeof fetch("data:,x"));
        return results;
      })()
    JS
  end

  # The window's member is the bare global itself, and its descriptor says so.
  def test_a_window_member_is_the_bare_global_and_its_descriptor
    assert_equal([true, true, true, true], @h.evaluate(<<~JS))
      (() => [window.fetch === fetch, window.setTimeout === setTimeout,
              Object.getOwnPropertyDescriptor(window, "fetch").value === window.fetch,
              Object.getOwnPropertyDescriptors(window).setTimeout.value === window.setTimeout])()
    JS
  end
end
