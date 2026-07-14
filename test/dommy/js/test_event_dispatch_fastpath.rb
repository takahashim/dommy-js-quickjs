# frozen_string_literal: true

require "test_helper"

# The unlistened-dispatch fast path (docs/event-dispatch-fastpath.md): a
# namespaced (colon) event type nobody listens for dispatches in one crossing
# with no cache invalidation. These tests pin the correctness edges: the fast
# path must never swallow a real listener (JS- or Ruby-registered), and the
# defaultPrevented shadow must track preventDefault / re-dispatch / initEvent.
class Dommy::Js::TestEventDispatchFastpath < Minitest::Test
  def setup
    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='x'>hi</div></body></html>"
    )
  end

  def teardown
    @h&.dispose
  end

  def test_unlistened_namespaced_dispatch_returns_true_and_default_prevented_false
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var ev = new CustomEvent("app:ping", {cancelable: true});
        return document.getElementById("x").dispatchEvent(ev) === true && ev.defaultPrevented === false
      })()
    JS
  end

  def test_listener_still_fires_and_can_cancel
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var el = document.getElementById("x");
        el.addEventListener("app:cancel-me", (e) => e.preventDefault());
        var ev = new CustomEvent("app:cancel-me", {cancelable: true});
        return el.dispatchEvent(ev) === false && ev.defaultPrevented === true
      })()
    JS
  end

  def test_listener_added_after_fast_dispatch_fires_on_the_next_dispatch
    assert_equal 1, @h.evaluate(<<~JS)
      (() => {
        var el = document.getElementById("x");
        var hits = 0;
        el.dispatchEvent(new CustomEvent("app:late"));
        el.addEventListener("app:late", () => { hits += 1; });
        el.dispatchEvent(new CustomEvent("app:late"));
        return hits
      })()
    JS
  end

  def test_ruby_side_listener_disables_the_fast_path
    hits = 0
    @h.window.document.add_event_listener("app:ruby") { hits += 1 }
    @h.execute('document.getElementById("x").dispatchEvent(new CustomEvent("app:ruby", {bubbles: true}));')
    assert_equal 1, hits
  end

  def test_pre_canceled_event_dispatch_returns_false
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var ev = new CustomEvent("app:pre", {cancelable: true});
        ev.preventDefault();
        return document.getElementById("x").dispatchEvent(ev) === false && ev.defaultPrevented === true
      })()
    JS
  end

  def test_prevent_default_after_fast_dispatch_updates_default_prevented
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var ev = new CustomEvent("app:after", {cancelable: true});
        document.getElementById("x").dispatchEvent(ev);
        ev.preventDefault();
        return ev.defaultPrevented === true
      })()
    JS
  end

  def test_legacy_return_value_after_fast_dispatch_updates_default_prevented
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var ev = new CustomEvent("app:legacy", {cancelable: true});
        document.getElementById("x").dispatchEvent(ev);
        ev.returnValue = false;
        return ev.defaultPrevented === true
      })()
    JS
  end

  def test_redispatch_through_slow_path_reads_live_state
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var el = document.getElementById("x");
        var ev = new CustomEvent("app:redispatch", {cancelable: true});
        el.dispatchEvent(ev); // fast: plants a false shadow
        el.addEventListener("app:redispatch", (e) => e.preventDefault());
        return el.dispatchEvent(ev) === false && ev.defaultPrevented === true
      })()
    JS
  end

  def test_stop_propagation_flag_resets_when_dispatch_completes
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var parent = document.getElementById("x");
        var child = document.createElement("span");
        parent.appendChild(child);
        var stopOnce = (e) => { e.stopPropagation(); child.removeEventListener("app:stop", stopOnce); };
        var bubbled = 0;
        child.addEventListener("app:stop", stopOnce);
        parent.addEventListener("app:stop", () => { bubbled += 1; });
        var ev = new CustomEvent("app:stop", {bubbles: true});
        child.dispatchEvent(ev); // stopped by the child listener
        var afterFirst = ev.cancelBubble; // spec: flag unset at dispatch end
        child.dispatchEvent(ev); // reused event object must propagate again
        return afterFirst === false && bubbled === 1;
      })()
    JS
  end

  def test_prototype_extracted_dispatch_event_handles_js_events
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var el = document.getElementById("x");
        var got = null;
        el.addEventListener("app:proto", (e) => { got = e; e.preventDefault(); });
        var ev = new CustomEvent("app:proto", {cancelable: true});
        var r = EventTarget.prototype.dispatchEvent.call(el, ev);
        return r === false && got === ev && ev.defaultPrevented === true;
      })()
    JS
  end

  def test_init_custom_event_after_fast_dispatch_drops_the_shadow
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var ev = document.createEvent("CustomEvent");
        ev.initCustomEvent("app:shadow", false, true, null);
        ev.preventDefault(); // canceled
        document.getElementById("x").dispatchEvent(ev); // fast: shadow planted (true)
        ev.initCustomEvent("app:shadow", false, false, null); // host resets canceled
        return ev.defaultPrevented === false;
      })()
    JS
  end

  def test_colonless_types_keep_the_classic_path
    assert_equal true, @h.evaluate(<<~JS)
      (() => {
        var el = document.getElementById("x");
        var seen = false;
        el.addEventListener("click", () => { seen = true; });
        el.dispatchEvent(new Event("click"));
        return seen
      })()
    JS
  end
end
