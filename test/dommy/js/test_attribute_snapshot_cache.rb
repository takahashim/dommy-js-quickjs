# frozen_string_literal: true

require "test_helper"

# The JS-side attribute-snapshot cache: an element proxy caches its full
# attribute map on first getAttribute/hasAttribute (one __rb_host_attrs
# crossing), invalidated by a global DOM-epoch counter that is bumped by
# mutating proxy operations and by every Ruby->JS entry. These tests pin the
# staleness/correctness contract — a cached read must never return a value the
# live DOM no longer holds, whether the mutation came from the same proxy, a
# different proxy (classList), a property write, or Ruby between executions.
class Dommy::Js::TestAttributeSnapshotCache < Minitest::Test
  PAGE = <<~HTML
    <html><body>
      <div id="el" class="a b" data-foo="bar" title="t"></div>
    </body></html>
  HTML

  def setup
    @win = Dommy.parse(PAGE)
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
    @rt.define_host_object("document", @win.document)
  end

  def teardown
    @rt&.dispose
  end

  # 1. Warm path: the second read is answered from the snapshot and must agree
  #    with the first.
  def test_repeated_get_attribute_returns_the_same_value
    assert_equal %w[bar bar], @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        return [el.getAttribute("data-foo"), el.getAttribute("data-foo")];
      })()
    JS
  end

  # 2. setAttribute must invalidate the snapshot within the same script.
  def test_set_attribute_then_read_in_same_script
    assert_equal "baz", @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        el.getAttribute("data-foo");           // warm the cache
        el.setAttribute("data-foo", "baz");
        return el.getAttribute("data-foo");
      })()
    JS
    assert_equal "baz", @win.document.get_element_by_id("el").get_attribute("data-foo")
  end

  # 3. removeAttribute / toggleAttribute must invalidate too.
  def test_remove_attribute_then_has_attribute
    assert_equal false, @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        if (!el.hasAttribute("title")) throw new Error("precondition: title present");
        el.removeAttribute("title");
        return el.hasAttribute("title");
      })()
    JS
  end

  def test_toggle_attribute_then_has_attribute
    assert_equal [true, false], @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        el.hasAttribute("hidden");             // warm the cache (miss)
        el.toggleAttribute("hidden");          // on
        const on = el.hasAttribute("hidden");
        el.toggleAttribute("hidden");          // off again
        return [on, el.hasAttribute("hidden")];
      })()
    JS
  end

  # 4. A mutation through a DIFFERENT proxy (the DOMTokenList) must be visible
  #    to the element proxy's cached getAttribute.
  def test_class_list_mutation_is_visible_through_get_attribute
    assert_equal "a b x", @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        el.getAttribute("class");              // warm the cache
        el.classList.add("x");
        return el.getAttribute("class");
      })()
    JS
  end

  # 5. Ruby-side mutation between two JS entries: every Ruby->JS entry bumps
  #    the epoch, so the second evaluate must see the Ruby-written value.
  def test_ruby_mutation_between_executions_is_visible
    @rt.execute(<<~JS)
      const el = document.getElementById("el");
      globalThis.__first = el.getAttribute("data-foo");
    JS
    assert_equal "bar", @rt.evaluate("globalThis.__first")

    @win.document.get_element_by_id("el").set_attribute("data-foo", "from-ruby")

    assert_equal "from-ruby",
                 @rt.evaluate('document.getElementById("el").getAttribute("data-foo")')
  end

  # 6. A property write through the proxy (reflected attribute) must invalidate.
  def test_property_write_then_get_attribute
    assert_equal "n", @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        el.getAttribute("id");                 // warm the cache
        el.id = "n";
        return el.getAttribute("id");
      })()
    JS
    assert_equal "n", @win.document.query_selector("div").get_attribute("id")
  end

  # 7. HTML elements match attribute names case-insensitively — the snapshot
  #    must honor that, not become an accidental case-sensitive Map lookup.
  def test_get_attribute_is_case_insensitive_on_html_elements
    assert_equal %w[bar bar], @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        return [el.getAttribute("DATA-FOO"), el.getAttribute("Data-Foo")];
      })()
    JS
    assert_equal true,
                 @rt.evaluate('document.getElementById("el").hasAttribute("DATA-FOO")')
  end

  # 8. Missing attribute: null from getAttribute, false from hasAttribute —
  #    both on the cold crossing and on the warm cached path.
  def test_missing_attribute_is_null_and_has_attribute_false
    assert_equal [nil, false, nil, false], @rt.evaluate(<<~JS)
      (() => {
        const el = document.getElementById("el");
        return [el.getAttribute("nope"), el.hasAttribute("nope"),
                el.getAttribute("nope"), el.hasAttribute("nope")];
      })()
    JS
  end

  # 9. SVG (foreign-namespace) elements skip the snapshot —
  #    Element#__js_attribute_snapshot__ returns nil for them — but must still
  #    answer getAttribute correctly per call, matching what Dommy's Ruby-side
  #    Element#get_attribute answers (per-call bridge parity).
  def test_svg_element_answers_get_attribute_via_uncached_path
    js_answers = @rt.evaluate(<<~JS)
      (() => {
        const svg = document.getElementById("el").appendChild(
          document.createElementNS("http://www.w3.org/2000/svg", "svg"));
        svg.setAttribute("viewBox", "0 0 10 10");
        return [svg.getAttribute("viewBox"),
                svg.getAttribute("viewBox"),        // repeat read stays correct
                svg.getAttribute("viewbox")];
      })()
    JS
    svg = @win.document.query_selector("svg")
    assert_nil svg.__js_attribute_snapshot__, "SVG must stay on the uncached path"
    assert_equal ["0 0 10 10", "0 0 10 10", svg.get_attribute("viewbox")], js_answers
  end

  # 9b. And an SVG mutation is immediately visible (no stale snapshot to serve).
  def test_svg_element_mutation_is_immediately_visible
    assert_equal ["0 0 10 10", "0 0 20 20"], @rt.evaluate(<<~JS)
      (() => {
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        svg.setAttribute("viewBox", "0 0 10 10");
        const before = svg.getAttribute("viewBox");
        svg.setAttribute("viewBox", "0 0 20 20");
        return [before, svg.getAttribute("viewBox")];
      })()
    JS
  end
end
