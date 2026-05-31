# frozen_string_literal: true

require "test_helper"

# Authors components in *JSX* and runs them on Dommy + QuickJS. JSX isn't valid
# JS, so it's transpiled to React.createElement calls first — by a tiny sucrase
# bundle (~200 KB vs @babel/standalone's ~3 MB, carrying only the JSX transform;
# see script/build_jsx_transform.sh) loaded INTO the VM as a vendored asset.
# This keeps the whole pipeline pure Ruby + RubyGems: the quickjs gem runs the
# JS; no Node, no native binary, no extra gem. Skips unless the bundles are
# vendored under test/fixtures/ (build the transpiler with the script above; for
# React: curl -sL https://unpkg.com/react@18/umd/react.production.min.js …).
class Dommy::Js::TestJsxIntegration < Minitest::Test
  JSX_TRANSFORM = File.expand_path("../../fixtures/jsx-transform.umd.js", __dir__)
  REACT = File.expand_path("../../fixtures/react.umd.js", __dir__)
  REACT_DOM = File.expand_path("../../fixtures/react-dom.umd.js", __dir__)

  def setup
    unless [JSX_TRANSFORM, REACT, REACT_DOM].all? { |f| File.exist?(f) }
      skip "JSX bundles not vendored (jsx-transform + react + react-dom)"
    end

    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='root'></div></body></html>"
    )
    @h.load_script(JSX_TRANSFORM)
    @h.load_script(REACT)
    @h.load_script(REACT_DOM)
  end

  def teardown
    @h&.dispose
  end

  # Transpile JSX → JS (classic React.createElement) in the VM, then run it.
  def run_jsx(source)
    @h.execute("eval(globalThis.transformJSX(#{source.to_json}));")
    @h.pump(rounds: 20)
  end

  def test_transpiles_jsx
    jsx = %q{const x = <a href="/y">z</a>;}
    code = @h.evaluate("globalThis.transformJSX(#{jsx.to_json})")
    assert_includes code, "React.createElement('a'"
    assert_includes code, 'href: "/y"'
    assert_empty @h.errors, @h.error_report
  end

  # A JSX element tree renders through React to the DOM.
  def test_jsx_renders
    run_jsx(<<~JSX)
      const App = () => (
        <div className="box">
          <h1>Hello JSX</h1>
          <span>{1 + 2}</span>
        </div>
      );
      ReactDOM.createRoot(document.getElementById("root")).render(<App />);
    JSX
    assert_equal '<div class="box"><h1>Hello JSX</h1><span>3</span></div>',
                 @h.window.document.get_element_by_id("root").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # A JSX component with hooks, an event handler, and conditional rendering is
  # interactive after transpilation.
  def test_jsx_component_with_hooks_and_events
    run_jsx(<<~JSX)
      const { useState } = React;
      function Counter() {
        const [n, setN] = useState(0);
        return (
          <div>
            <span id="count">{n}</span>
            <button id="inc" onClick={() => setN(n + 1)}>+</button>
            {n >= 2 ? <strong id="big">big</strong> : null}
          </div>
        );
      }
      ReactDOM.createRoot(document.getElementById("root")).render(<Counter />);
    JSX
    assert_equal "0", @h.window.document.get_element_by_id("count").text_content
    assert_nil @h.window.document.get_element_by_id("big")

    @h.execute('document.getElementById("inc").click();')
    @h.pump(rounds: 20)
    @h.execute('document.getElementById("inc").click();')
    @h.pump(rounds: 20)

    assert_equal "2", @h.window.document.get_element_by_id("count").text_content
    assert_equal "big", @h.window.document.get_element_by_id("big")&.text_content
    assert_empty @h.errors, @h.error_report
  end

  # JSX composition: a parent passes props/children to a child component.
  def test_jsx_composition_with_props
    run_jsx(<<~JSX)
      const Item = ({ label, children }) => <li className="item">{label}: {children}</li>;
      const List = () => (
        <ul id="list">
          <Item label="a">1</Item>
          <Item label="b">2</Item>
        </ul>
      );
      ReactDOM.createRoot(document.getElementById("root")).render(<List />);
    JSX
    assert_equal '<li class="item">a: 1</li><li class="item">b: 2</li>',
                 @h.window.document.get_element_by_id("list").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # A multi-component JSX app — Context + useReducer store, a controlled form,
  # a memoized derived list, keyed items, conditional empty state — exercised end
  # to end: add via the form, toggle, filter, delete.
  def test_multi_component_jsx_app
    run_jsx(<<~JSX)
      const { useReducer, useMemo, createContext, useContext, useState } = React;
      const Store = createContext(null);
      function reducer(s, a) {
        switch (a.type) {
          case "add":    return { ...s, todos: [...s.todos, { id: s.seq, text: a.text, done: false }], seq: s.seq + 1 };
          case "toggle": return { ...s, todos: s.todos.map(t => t.id === a.id ? { ...t, done: !t.done } : t) };
          case "remove": return { ...s, todos: s.todos.filter(t => t.id !== a.id) };
          case "filter": return { ...s, filter: a.filter };
          default: return s;
        }
      }
      const Form = () => {
        const { dispatch } = useContext(Store);
        const [text, setText] = useState("");
        return (
          <form id="form" onSubmit={(e) => { e.preventDefault(); if (text) { dispatch({ type: "add", text }); setText(""); } }}>
            <input id="new" value={text} onChange={(e) => setText(e.target.value)} />
          </form>
        );
      };
      const Item = ({ todo }) => {
        const { dispatch } = useContext(Store);
        return (
          <li className={todo.done ? "done" : "todo"}>
            <span>{todo.text}</span>
            <button className="tog" onClick={() => dispatch({ type: "toggle", id: todo.id })}>t</button>
            <button className="del" onClick={() => dispatch({ type: "remove", id: todo.id })}>d</button>
          </li>
        );
      };
      const List = () => {
        const { state } = useContext(Store);
        const shown = useMemo(() => state.todos.filter(t => state.filter === "all" || (state.filter === "done" ? t.done : !t.done)), [state.todos, state.filter]);
        return shown.length ? <ul id="list">{shown.map(t => <Item key={t.id} todo={t} />)}</ul> : <p id="empty">empty</p>;
      };
      const App = () => {
        const [state, dispatch] = useReducer(reducer, { todos: [{ id: 0, text: "first", done: false }], filter: "all", seq: 1 });
        const remaining = state.todos.filter(t => !t.done).length;
        return (
          <Store.Provider value={{ state, dispatch }}>
            <span id="remaining">{remaining}</span>
            <Form />
            <div id="filters">{["all", "active"].map(f => <button key={f} data-f={f} onClick={() => dispatch({ type: "filter", filter: f })}>{f}</button>)}</div>
            <List />
          </Store.Provider>
        );
      };
      ReactDOM.createRoot(document.getElementById("root")).render(<App />);
    JSX
    doc = @h.window.document
    assert_equal 1, doc.query_selector_all("#list li").size
    assert_equal "1", doc.get_element_by_id("remaining").text_content

    # Add a task through the controlled form.
    @h.execute(<<~JS)
      const i = document.getElementById('new');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(i, 'second');
      i.dispatchEvent(new Event('input', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    @h.execute("document.getElementById('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));")
    @h.pump(rounds: 20)
    assert_equal 2, doc.query_selector_all("#list li").size
    assert_equal "2", doc.get_element_by_id("remaining").text_content

    # Toggle the first task done, then filter to active (hides it).
    @h.execute("document.querySelectorAll('.tog')[0].click();")
    @h.pump(rounds: 20)
    assert_equal "1", doc.get_element_by_id("remaining").text_content
    @h.execute("document.querySelector('[data-f=active]').click();")
    @h.pump(rounds: 20)
    assert_equal 1, doc.query_selector_all("#list li").size

    # Delete the remaining shown task → conditional empty state.
    @h.execute("document.querySelectorAll('.del')[0].click();")
    @h.pump(rounds: 20)
    assert_equal "empty", doc.get_element_by_id("empty")&.text_content
    assert_empty @h.errors, @h.error_report
  end
end
