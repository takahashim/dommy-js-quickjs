# frozen_string_literal: true

require "test_helper"

# Drives the *real* Solid.js bundle on Dommy + QuickJS. Solid is a fine-grained
# reactive framework: instead of a virtual DOM it compiles to direct DOM
# operations driven by signals (no diffing — a signal change patches exactly the
# text node / attribute it feeds). This exercises a very different rendering
# model from React's vdom and Vue's proxy reactivity.
#
# We use Solid's official *no-build* path — the `html` tagged-template renderer
# (solid-js/html) — so no JSX compiler is needed (Solid's JSX requires the
# Solid-specific dom-expressions transform, which the React/sucrase path can't
# do). The bundle wraps solid-js + solid-js/web + solid-js/store + solid-js/html
# (unpkg.com/solid-js@1 CJS builds) in a small CommonJS shim and exposes
# window.{Solid,SolidWeb,SolidStore,html} — see the fixture header for provenance.
#
# Solid schedules effects/renders on the microtask queue, so each interaction is
# followed by a pump to let the reactive graph settle (the standard harness
# pattern).
class Dommy::Js::TestSolidIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/solid.global.js", __dir__)

  def setup
    skip "Solid bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)
    @h = Dommy::Js::BrowserHarness.new("<!DOCTYPE html><html><head></head><body><div id='app'></div></body></html>")
    @h.load_script(BUNDLE)
    @h.pump(rounds: 5)
  end

  def teardown
    @h&.dispose
  end

  def doc = @h.window.document

  def text_of(sel) = @h.evaluate("(document.querySelector(#{sel.inspect})||{}).textContent")

  # Signals, effects, memos, batch, untrack — the reactivity core (no DOM).
  def test_core_reactivity
    @h.evaluate(<<~JS)
      globalThis.__log = []; globalThis.__set = null; globalThis.__sum = null;
      Solid.createRoot(() => {
        const [count, setCount] = Solid.createSignal(0);
        const [a, setA] = Solid.createSignal(2);
        const sum = Solid.createMemo(() => a() + 3);
        globalThis.__set = setCount; globalThis.__setA = setA; globalThis.__sum = sum;
        Solid.createEffect(() => { globalThis.__log.push(count()); });
      });
    JS
    @h.pump(rounds: 10)
    assert_equal [0], JSON.parse(@h.evaluate("JSON.stringify(globalThis.__log)"))

    @h.evaluate("globalThis.__set(1); true")
    @h.pump(rounds: 10)
    @h.evaluate("globalThis.__set(2); true")
    @h.pump(rounds: 10)
    assert_equal [0, 1, 2], JSON.parse(@h.evaluate("JSON.stringify(globalThis.__log)"))

    # memo recomputes on dependency change
    assert_equal 5, @h.evaluate("globalThis.__sum()")
    @h.evaluate("globalThis.__setA(10); true")
    @h.pump(rounds: 10)
    assert_equal 13, @h.evaluate("globalThis.__sum()")
    assert_empty @h.errors, @h.error_report
  end

  # render() into the DOM, an onClick handler mutating a signal, and a
  # fine-grained text update (only the text node patches, no re-render).
  def test_render_and_event
    @h.evaluate(<<~JS)
      const { createSignal } = Solid;
      SolidWeb.render(() => {
        const [count, setCount] = createSignal(0);
        return html`<button id="btn" onClick=${() => setCount(count() + 1)}>Count: ${count}</button>`;
      }, document.getElementById("app"));
    JS
    @h.pump(rounds: 15)
    assert_equal "Count: 0", text_of("#btn")

    @h.execute("document.getElementById('btn').click();")
    @h.pump(rounds: 15)
    assert_equal "Count: 1", text_of("#btn")

    @h.execute("document.getElementById('btn').click();")
    @h.pump(rounds: 15)
    assert_equal "Count: 2", text_of("#btn")
    assert_empty @h.errors, @h.error_report
  end

  # <Show> (conditional + fallback) and a component with a reactive prop.
  def test_show_and_component_props
    @h.evaluate(<<~JS)
      const { createSignal, Show, createMemo } = Solid;
      globalThis.__toggle = null;
      function Label(props) { return html`<span class="lbl">${() => props.text}</span>`; }
      SolidWeb.render(() => {
        const [open, setOpen] = createSignal(true);
        const [n, setN] = createSignal(1);
        globalThis.__toggle = () => setOpen(!open());
        globalThis.__bump = () => setN(n() + 1);
        const label = createMemo(() => "N=" + n());
        return html`<div>
          <${Label} text=${label} />
          <${Show} when=${open} fallback=${html`<p id="f">hidden</p>`}>
            <p id="shown">VISIBLE</p>
          <//>
        </div>`;
      }, document.getElementById("app"));
    JS
    @h.pump(rounds: 20)
    assert_equal "N=1", text_of(".lbl")
    refute_nil doc.get_element_by_id("shown")
    assert_nil doc.get_element_by_id("f")

    # reactive prop updates through the component boundary
    @h.evaluate("globalThis.__bump(); true")
    @h.pump(rounds: 20)
    assert_equal "N=2", text_of(".lbl")

    # Show swaps to the fallback
    @h.evaluate("globalThis.__toggle(); true")
    @h.pump(rounds: 20)
    assert_nil doc.get_element_by_id("shown")
    refute_nil doc.get_element_by_id("f")
    assert_empty @h.errors, @h.error_report
  end

  # <For> list reconciliation as the backing array grows and shrinks. The
  # shrink path is the one that used to throw "cannot convert symbol to number"
  # in proxy-reactive frameworks before the bridge identity fix.
  def test_for_list
    @h.evaluate(<<~JS)
      const { createSignal, For } = Solid;
      globalThis.__add = null; globalThis.__removeFirst = null;
      SolidWeb.render(() => {
        const [items, setItems] = createSignal(["a", "b", "c"]);
        globalThis.__add = () => setItems([...items(), "z"]);
        globalThis.__removeFirst = () => setItems(items().slice(1));
        return html`<ul id="list"><${For} each=${items}>${(item, i) =>
          html`<li class="row">${i}:${item}</li>`
        }<//></ul>`;
      }, document.getElementById("app"));
    JS
    @h.pump(rounds: 20)
    rows = -> { doc.query_selector_all("#list .row").map(&:text_content) }
    assert_equal %w[0:a 1:b 2:c], rows.call

    @h.evaluate("globalThis.__add(); true")
    @h.pump(rounds: 20)
    assert_equal %w[0:a 1:b 2:c 3:z], rows.call

    @h.evaluate("globalThis.__removeFirst(); true")
    @h.pump(rounds: 20)
    assert_equal %w[0:b 1:c 2:z], rows.call
    assert_empty @h.errors, @h.error_report
  end

  # createStore: nested, fine-grained reactive state with path setters — the
  # hardest part of Solid's reactivity to host. A deep-path set patches only the
  # text node bound to that exact field.
  def test_store_nested_state
    @h.evaluate(<<~JS)
      const { For } = Solid;
      const { createStore } = SolidStore;
      globalThis.__bumpAge = null; globalThis.__addTodo = null; globalThis.__toggleFirst = null;
      SolidWeb.render(() => {
        const [state, setState] = createStore({
          user: { name: "Ann", age: 30 },
          todos: [{ text: "x", done: false }],
        });
        globalThis.__bumpAge = () => setState("user", "age", a => a + 1);
        globalThis.__addTodo = () => setState("todos", t => [...t, { text: "y", done: false }]);
        globalThis.__toggleFirst = () => setState("todos", 0, "done", d => !d);
        return html`<div>
          <span id="who">${() => state.user.name}:${() => state.user.age}</span>
          <ul id="todos"><${For} each=${() => state.todos}>${(todo) =>
            html`<li class="t">${() => todo.text}-${() => todo.done ? "done" : "open"}</li>`
          }<//></ul>
        </div>`;
      }, document.getElementById("app"));
    JS
    @h.pump(rounds: 20)
    todos = -> { doc.query_selector_all("#todos .t").map(&:text_content) }
    assert_equal "Ann:30", text_of("#who")
    assert_equal %w[x-open], todos.call

    @h.evaluate("globalThis.__bumpAge(); true")
    @h.pump(rounds: 20)
    assert_equal "Ann:31", text_of("#who") # only age patched, name preserved

    @h.evaluate("globalThis.__addTodo(); true")
    @h.pump(rounds: 20)
    assert_equal %w[x-open y-open], todos.call

    @h.evaluate("globalThis.__toggleFirst(); true")
    @h.pump(rounds: 20)
    assert_equal %w[x-done y-open], todos.call # deep path set patches one row
    assert_empty @h.errors, @h.error_report
  end
end
