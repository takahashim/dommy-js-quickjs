# frozen_string_literal: true

require "test_helper"

# Drives the *real* Lit 3 bundle on Dommy + QuickJS. Lit is a Web Components
# library: LitElement subclasses are custom elements that render into a shadow
# root, driven by reactive properties; templates use the lit-html `html` tagged
# template, which clones a <template> element and walks its content with a
# TreeWalker to find binding markers. This exercises a different stack from the
# vdom (React) / proxy (Vue) / signal (Solid) frameworks: custom-element upgrade
# + lifecycle, shadow-DOM rendering, reactive-property accessors, and the
# <template>-content machinery.
#
# Lit is ESM-only; the fixture wraps the esm.sh bundle (lit.bundle.mjs +
# @lit/reactive-element css-tag.mjs) into a single global script — see the
# fixture header for provenance. Exposes window.Lit = { LitElement, html, css,
# render, nothing, noChange, svg, ... }.
#
# Lit schedules updates on the microtask queue, so each interaction is followed
# by a pump to let the reactive update settle (the standard harness pattern).
class Dommy::Js::TestLitIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/lit.global.js", __dir__)

  def setup
    skip "Lit bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)
    @h = Dommy::Js::BrowserHarness.new("<!DOCTYPE html><html><head></head><body><div id='app'></div></body></html>")
    @h.load_script(BUNDLE)
    @h.pump(rounds: 5)
  end

  def teardown
    @h&.dispose
  end

  def doc = @h.window.document

  def test_loads
    assert_equal "object", @h.evaluate("typeof Lit")
    assert_equal "function", @h.evaluate("typeof Lit.LitElement")
    assert_equal "function", @h.evaluate("typeof Lit.html")
    assert_equal "function", @h.evaluate("typeof Lit.render")
    assert_empty @h.errors, @h.error_report
  end

  # lit-html standalone: render a template, re-render with new data (the part is
  # reused and patched in place), an @event binding, a ?boolean attribute, and a
  # mapped list. This is the <template>-clone + TreeWalker path end to end.
  def test_lit_html_render
    @h.evaluate(<<~JS)
      const { html, render } = Lit;
      globalThis.__rerender = null; globalThis.__clicked = false;
      const tpl = (name, n, items) => html`
        <h1>Hello ${name}</h1>
        <p class="count" ?data-zero=${n === 0}>n=${n}</p>
        <ul>${items.map((it) => html`<li class="row">${it}</li>`)}</ul>
        <button id="b" @click=${() => { globalThis.__clicked = true; }}>go</button>`;
      globalThis.__rerender = (name, n, items) => render(tpl(name, n, items), document.getElementById("app"));
      globalThis.__rerender("World", 0, ["a", "b"]);
    JS
    @h.pump(rounds: 15)
    assert_equal "Hello World", @h.evaluate('document.querySelector("#app h1").textContent').strip
    assert_equal "n=0", @h.evaluate('document.querySelector("#app .count").textContent')
    assert_equal %w[a b], JSON.parse(@h.evaluate('JSON.stringify([...document.querySelectorAll("#app .row")].map(l=>l.textContent))'))

    @h.evaluate('globalThis.__rerender("Lit", 3, ["x","y","z"]); true')
    @h.pump(rounds: 15)
    assert_equal "Hello Lit", @h.evaluate('document.querySelector("#app h1").textContent').strip
    assert_equal "n=3", @h.evaluate('document.querySelector("#app .count").textContent')
    assert_equal %w[x y z], JSON.parse(@h.evaluate('JSON.stringify([...document.querySelectorAll("#app .row")].map(l=>l.textContent))'))

    @h.execute('document.getElementById("b").click();')
    @h.pump(rounds: 10)
    assert @h.evaluate("globalThis.__clicked"), "@click handler should fire"
    assert_empty @h.errors, @h.error_report
  end

  # A LitElement custom element: definition + upgrade, shadow-DOM render,
  # reactive property → re-render, an event inside the shadow tree, and
  # attribute → property reflection with a type converter.
  def test_lit_element_lifecycle
    @h.evaluate(<<~JS)
      const { LitElement, html, css } = Lit;
      class MyCounter extends LitElement {
        static properties = { name: {}, count: { type: Number } };
        static styles = css`span { color: red; }`;
        constructor() { super(); this.name = "Lit"; this.count = 0; }
        inc() { this.count++; }
        render() {
          return html`<div class="box">
            <span id="label">${this.name}: ${this.count}</span>
            <button id="inc" @click=${() => this.inc()}>+</button>
          </div>`;
        }
      }
      customElements.define("my-counter", MyCounter);
      const el = document.createElement("my-counter");
      el.id = "c1";
      document.body.appendChild(el);
      globalThis.__el = el;
    JS
    @h.pump(rounds: 20)
    label = -> { @h.evaluate('globalThis.__el.shadowRoot.querySelector("#label").textContent') }

    assert @h.evaluate('customElements.get("my-counter") !== undefined'), "element should be defined"
    assert @h.evaluate("!!globalThis.__el.shadowRoot"), "should have a shadow root"
    assert_equal "Lit: 0", label.call

    # reactive property assignment triggers a re-render
    @h.evaluate("globalThis.__el.count = 5; true")
    @h.pump(rounds: 20)
    assert_equal "Lit: 5", label.call

    # an event inside the shadow tree drives the component method
    @h.evaluate('globalThis.__el.shadowRoot.querySelector("#inc").click(); true')
    @h.pump(rounds: 20)
    assert_equal "Lit: 6", label.call

    # attribute → property reflection, with the Number converter
    @h.evaluate('globalThis.__el.setAttribute("count", "42"); true')
    @h.pump(rounds: 20)
    assert_equal "Lit: 42", label.call
    assert_equal 42, @h.evaluate("globalThis.__el.count")

    # the styles ended up injected as a <style> in the shadow root (Dommy has no
    # constructable-stylesheet support, so Lit takes the <style> fallback path)
    assert_equal 1, @h.evaluate('globalThis.__el.shadowRoot.querySelectorAll("style").length')
    assert_empty @h.errors, @h.error_report
  end
end
