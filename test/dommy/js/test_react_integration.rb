# frozen_string_literal: true

require "test_helper"

# Drives the *real* React 18 UMD build (react + react-dom) on Dommy + QuickJS.
# React-DOM is one of the most demanding DOM consumers — the full mutation API,
# a delegated synthetic-event system, hooks-driven re-renders, and controlled
# inputs (its value tracker) — so this pins how far the bridge can host it.
# Skips unless both bundles are vendored:
#   curl -sL https://unpkg.com/react@18/umd/react.production.min.js \
#     -o test/fixtures/react.umd.js
#   curl -sL https://unpkg.com/react-dom@18/umd/react-dom.production.min.js \
#     -o test/fixtures/react-dom.umd.js
class Dommy::Js::TestReactIntegration < Minitest::Test
  REACT = File.expand_path("../../fixtures/react.umd.js", __dir__)
  REACT_DOM = File.expand_path("../../fixtures/react-dom.umd.js", __dir__)
  # react-dom/server (legacy browser build: renderToString / renderToStaticMarkup):
  #   curl -sL https://unpkg.com/react-dom@18/umd/react-dom-server-legacy.browser.production.min.js \
  #     -o test/fixtures/react-dom-server.umd.js
  REACT_DOM_SERVER = File.expand_path("../../fixtures/react-dom-server.umd.js", __dir__)

  def setup
    skip "React bundles not vendored" unless File.exist?(REACT) && File.exist?(REACT_DOM)

    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='root'></div></body></html>"
    )
    @h.load_script(REACT)
    @h.load_script(REACT_DOM)
  end

  def teardown
    @h&.dispose
  end

  def root_html = @h.window.document.get_element_by_id("root").inner_html

  def render(js_component_expr)
    @h.execute("ReactDOM.createRoot(document.getElementById('root')).render(#{js_component_expr});")
    @h.pump(rounds: 20)
  end

  def test_react_loads
    assert_equal "object", @h.evaluate("typeof React")
    assert_equal "function", @h.evaluate("typeof ReactDOM.createRoot")
    assert_empty @h.errors, @h.error_report
  end

  # createRoot().render() commits an element tree to the real DOM.
  def test_renders_element_tree
    render("React.createElement('div', { className: 'box' }, React.createElement('h1', null, 'Hello'))")
    assert_equal '<div class="box"><h1>Hello</h1></div>', root_html
    assert_empty @h.errors, @h.error_report
  end

  # React's delegated synthetic-event system: a single root listener dispatches
  # onClick to the right component handler.
  def test_synthetic_click_event
    @h.execute(<<~JS)
      const e = React.createElement;
      globalThis.__App = () => e('button', { id: 'btn', onClick: () => { document.getElementById('btn').textContent = 'clicked'; } }, 'go');
    JS
    render("React.createElement(globalThis.__App)")
    assert_equal "go", @h.window.document.get_element_by_id("btn").text_content

    @h.execute("document.getElementById('btn').click();")
    @h.pump(rounds: 20)
    assert_equal "clicked", @h.window.document.get_element_by_id("btn").text_content
    assert_empty @h.errors, @h.error_report
  end

  # useState + an event-driven re-render: clicking updates state and the DOM
  # reflects the new render.
  def test_use_state_rerender
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__Counter = () => {
        const [n, setN] = useState(0);
        return e('button', { id: 'c', onClick: () => setN(n + 1) }, 'n=' + n);
      };
    JS
    render("React.createElement(globalThis.__Counter)")
    assert_equal "n=0", @h.window.document.get_element_by_id("c").text_content

    @h.execute("document.getElementById('c').click();")
    @h.pump(rounds: 20)
    assert_equal "n=1", @h.window.document.get_element_by_id("c").text_content

    @h.execute("document.getElementById('c').click();")
    @h.pump(rounds: 20)
    assert_equal "n=2", @h.window.document.get_element_by_id("c").text_content
    assert_empty @h.errors, @h.error_report
  end

  # useEffect runs after commit and re-runs when its dependency changes.
  def test_use_effect
    @h.execute(<<~JS)
      const { createElement: e, useState, useEffect } = React;
      globalThis.__effects = 0;
      globalThis.__Fx = () => {
        const [n, setN] = useState(0);
        useEffect(() => { globalThis.__effects++; }, [n]);
        return e('button', { id: 'fx', onClick: () => setN(n + 1) }, String(n));
      };
    JS
    render("React.createElement(globalThis.__Fx)")
    assert_equal 1, @h.evaluate("globalThis.__effects")

    @h.execute("document.getElementById('fx').click();")
    @h.pump(rounds: 20)
    assert_equal 2, @h.evaluate("globalThis.__effects")
    assert_empty @h.errors, @h.error_report
  end

  # Conditional rendering swaps subtrees (mount/unmount via the reconciler).
  def test_conditional_rendering
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__Toggle = () => {
        const [on, setOn] = useState(false);
        return e('div', null,
          e('button', { id: 't', onClick: () => setOn(!on) }, 'toggle'),
          on ? e('span', { id: 'panel' }, 'OPEN') : null);
      };
    JS
    render("React.createElement(globalThis.__Toggle)")
    assert_nil @h.window.document.get_element_by_id("panel")

    @h.execute("document.getElementById('t').click();")
    @h.pump(rounds: 20)
    assert_equal "OPEN", @h.window.document.get_element_by_id("panel")&.text_content

    @h.execute("document.getElementById('t').click();")
    @h.pump(rounds: 20)
    assert_nil @h.window.document.get_element_by_id("panel")
    assert_empty @h.errors, @h.error_report
  end

  # A controlled input: the value reflects state, and editing it fires onChange
  # (React's value tracker, which wraps the prototype's `value` accessor, detects
  # the change). Typing is simulated the way React Testing Library does it — the
  # native prototype setter sets the value (bypassing React's own-property
  # wrapper so the tracker sees a change), then an `input` event is dispatched.
  def test_controlled_input_two_way_binding
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__Form = () => {
        const [text, setText] = useState("hi");
        return e('div', null,
          e('input', { id: 'inp', value: text, onChange: (ev) => setText(ev.target.value) }),
          e('span', { id: 'echo' }, text));
      };
    JS
    render("React.createElement(globalThis.__Form)")
    assert_equal "hi", @h.evaluate("document.getElementById('inp').value")
    assert_equal "hi", @h.window.document.get_element_by_id("echo").text_content

    @h.execute(<<~JS)
      const inp = document.getElementById('inp');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(inp, 'world');
      inp.dispatchEvent(new Event('input', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    # onChange fired → state updated → re-render reflects the new value.
    assert_equal "world", @h.window.document.get_element_by_id("echo").text_content
    assert_equal "world", @h.evaluate("document.getElementById('inp').value")
    assert_empty @h.errors, @h.error_report
  end

  # A controlled checkbox: `checked` reflects state and toggling fires onChange
  # (the value tracker handles `checked` like `value`).
  def test_controlled_checkbox
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__Cb = () => {
        const [on, setOn] = useState(false);
        return e('div', null,
          e('input', { id: 'cb', type: 'checkbox', checked: on, onChange: (ev) => setOn(ev.target.checked) }),
          e('span', { id: 's' }, on ? 'ON' : 'OFF'));
      };
    JS
    render("React.createElement(globalThis.__Cb)")
    assert_equal "OFF", @h.window.document.get_element_by_id("s").text_content

    @h.execute(<<~JS)
      const cb = document.getElementById('cb');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'checked').set.call(cb, true);
      cb.dispatchEvent(new Event('click', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    assert_equal "ON", @h.window.document.get_element_by_id("s").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Keyed-list reconciliation: appending and removing items updates the DOM
  # through React's keyed diff.
  def test_keyed_list_reconciliation
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__List = () => {
        const [items, setItems] = useState(["a", "b"]);
        return e('div', null,
          e('button', { id: 'add', onClick: () => setItems([...items, 'c']) }, '+'),
          e('button', { id: 'del', onClick: () => setItems(items.slice(1)) }, '-'),
          e('ul', { id: 'ul' }, items.map((x) => e('li', { key: x }, x))));
      };
    JS
    render("React.createElement(globalThis.__List)")
    assert_equal "<li>a</li><li>b</li>", @h.window.document.get_element_by_id("ul").inner_html

    @h.execute("document.getElementById('add').click();")
    @h.pump(rounds: 20)
    assert_equal "<li>a</li><li>b</li><li>c</li>", @h.window.document.get_element_by_id("ul").inner_html

    @h.execute("document.getElementById('del').click();")
    @h.pump(rounds: 20)
    assert_equal "<li>b</li><li>c</li>", @h.window.document.get_element_by_id("ul").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # useRef exposes the mounted DOM node; useContext reads a Provider value.
  def test_use_ref_and_use_context
    @h.execute(<<~JS)
      const { createElement: e, useRef, useEffect, useState, createContext, useContext } = React;
      const Ctx = createContext("default");
      const Child = () => e('span', { id: 'ctx' }, useContext(Ctx));
      globalThis.__App = () => {
        const ref = useRef(null);
        const [tag, setTag] = useState("");
        useEffect(() => { setTag(ref.current ? ref.current.tagName : "none"); }, []);
        return e(Ctx.Provider, { value: "provided" },
          e('input', { ref }),
          e('span', { id: 'tag' }, tag),
          e(Child));
      };
    JS
    render("React.createElement(globalThis.__App)")
    assert_equal "INPUT", @h.window.document.get_element_by_id("tag").text_content
    assert_equal "provided", @h.window.document.get_element_by_id("ctx").text_content
    assert_empty @h.errors, @h.error_report
  end

  # A Fragment groups children with no wrapper; useReducer updates on dispatch.
  def test_fragment_and_use_reducer
    @h.execute(<<~JS)
      const { createElement: e, Fragment, useReducer } = React;
      globalThis.__R = () => {
        const [n, dispatch] = useReducer((s, a) => s + a, 0);
        return e(Fragment, null,
          e('span', { id: 'x' }, String(n)),
          e('button', { id: 'b', onClick: () => dispatch(5) }, '+'));
      };
    JS
    render("React.createElement(globalThis.__R)")
    assert_equal "0", @h.window.document.get_element_by_id("x").text_content

    @h.execute("document.getElementById('b').click();")
    @h.pump(rounds: 20)
    assert_equal "5", @h.window.document.get_element_by_id("x").text_content
    assert_empty @h.errors, @h.error_report
  end

  # A form's onSubmit synthetic event fires (and preventDefault works).
  def test_form_on_submit
    @h.execute(<<~JS)
      const e = React.createElement;
      globalThis.__submitted = false;
      globalThis.__F = () => e('form', { id: 'f', onSubmit: (ev) => { ev.preventDefault(); globalThis.__submitted = true; } },
        e('button', { type: 'submit' }, 'go'));
    JS
    render("React.createElement(globalThis.__F)")
    @h.execute("document.getElementById('f').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));")
    @h.pump(rounds: 20)
    assert_equal true, @h.evaluate("globalThis.__submitted")
    assert_empty @h.errors, @h.error_report
  end

  # A controlled <select> reflects state and onChange updates it.
  def test_controlled_select
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__S = () => {
        const [v, setV] = useState("a");
        return e('div', null,
          e('select', { id: 'sel', value: v, onChange: (ev) => setV(ev.target.value) },
            e('option', { value: 'a' }, 'A'), e('option', { value: 'b' }, 'B')),
          e('span', { id: 'sv' }, v));
      };
    JS
    render("React.createElement(globalThis.__S)")
    assert_equal "a", @h.window.document.get_element_by_id("sv").text_content

    @h.execute(<<~JS)
      const sel = document.getElementById('sel');
      Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(sel, 'b');
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    assert_equal "b", @h.window.document.get_element_by_id("sv").text_content
    assert_empty @h.errors, @h.error_report
  end

  # createPortal renders children into a different container.
  def test_create_portal
    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='root'></div><div id='portal'></div></body></html>"
    )
    @h.load_script(REACT)
    @h.load_script(REACT_DOM)
    @h.execute(<<~JS)
      const e = React.createElement;
      globalThis.__P = () => e('div', null, 'main',
        ReactDOM.createPortal(e('span', { id: 'p' }, 'PORTALED'), document.getElementById('portal')));
    JS
    render("React.createElement(globalThis.__P)")
    assert_equal '<span id="p">PORTALED</span>', @h.window.document.get_element_by_id("portal").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # An error boundary catches a render error via getDerivedStateFromError.
  def test_error_boundary
    @h.execute(<<~JS)
      const { createElement: e, Component } = React;
      class Boom extends Component { render() { throw new Error('boom'); } }
      class EB extends Component {
        constructor(p) { super(p); this.state = { err: false }; }
        static getDerivedStateFromError() { return { err: true }; }
        render() { return this.state.err ? e('span', { id: 'eb' }, 'CAUGHT') : this.props.children; }
      }
      globalThis.__EB = () => e(EB, null, e(Boom));
    JS
    render("React.createElement(globalThis.__EB)")
    assert_equal "CAUGHT", @h.window.document.get_element_by_id("eb").text_content
  end

  # Rich props: a camelCase style object serializes to CSS text, an SVG subtree
  # gets the SVG namespace, and dangerouslySetInnerHTML injects raw markup.
  def test_style_svg_and_raw_html
    render(<<~JS.strip)
      React.createElement('div', null,
        React.createElement('p', { id: 'styled', style: { color: 'red', fontSize: '12px' } }, 'x'),
        React.createElement('svg', { id: 'svg' }, React.createElement('circle', { cx: 5, cy: 5, r: 5 })),
        React.createElement('div', { id: 'raw', dangerouslySetInnerHTML: { __html: '<b>bold</b>' } }))
    JS
    assert_equal "color:red;font-size:12px", @h.window.document.get_element_by_id("styled").get_attribute("style")
    assert_equal "http://www.w3.org/2000/svg", @h.evaluate("document.getElementById('svg').namespaceURI")
    assert_equal "<b>bold</b>", @h.window.document.get_element_by_id("raw").inner_html
    assert_empty @h.errors, @h.error_report
  end

  # Falsey/null props don't render attributes (disabled={false} / title={null}),
  # while data-* passes through.
  def test_boolean_and_null_attributes
    render("React.createElement('input', { id: 'i', disabled: false, title: null, 'data-x': 'y' })")
    el = @h.window.document.get_element_by_id("i")
    assert_nil el.get_attribute("disabled")
    assert_nil el.get_attribute("title")
    assert_equal "y", el.get_attribute("data-x")
    assert_empty @h.errors, @h.error_report
  end

  # Capture-phase handlers run before bubble: onClickCapture (parent) → onClick
  # (target) → onClick (parent bubble).
  def test_event_capture_phase_ordering
    @h.execute(<<~JS)
      const e = React.createElement;
      globalThis.__order = [];
      globalThis.__A = () => e('div', {
        onClickCapture: () => globalThis.__order.push('parent-capture'),
        onClick: () => globalThis.__order.push('parent-bubble'),
      }, e('button', { id: 'b', onClick: () => globalThis.__order.push('btn') }, 'x'));
    JS
    render("React.createElement(globalThis.__A)")
    @h.execute("document.getElementById('b').click();")
    @h.pump(rounds: 20)
    assert_equal %w[parent-capture btn parent-bubble], @h.evaluate("globalThis.__order")
    assert_empty @h.errors, @h.error_report
  end

  # React delegates events along the COMPONENT tree, not the DOM tree: a click on
  # a portaled child bubbles to the onClick of its React parent (in another
  # container).
  def test_portal_event_bubbles_to_react_parent
    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body><div id='root'></div><div id='portal'></div></body></html>"
    )
    @h.load_script(REACT)
    @h.load_script(REACT_DOM)
    @h.execute(<<~JS)
      const e = React.createElement;
      globalThis.__parentClicked = false;
      globalThis.__A = () => e('div', { onClick: () => { globalThis.__parentClicked = true; } },
        ReactDOM.createPortal(e('button', { id: 'pb' }, 'x'), document.getElementById('portal')));
    JS
    render("React.createElement(globalThis.__A)")
    @h.execute("document.getElementById('pb').click();")
    @h.pump(rounds: 20)
    assert_equal true, @h.evaluate("globalThis.__parentClicked")
    assert_empty @h.errors, @h.error_report
  end

  # Suspense shows a fallback then the resolved lazy component.
  def test_suspense_and_lazy
    @h.execute(<<~JS)
      const { createElement: e, Suspense, lazy } = React;
      const Lazy = lazy(() => Promise.resolve({ default: () => e('span', { id: 'lz' }, 'LOADED') }));
      globalThis.__Sus = () => e(Suspense, { fallback: e('span', { id: 'fb' }, 'loading') }, e(Lazy));
    JS
    render("React.createElement(globalThis.__Sus)")
    @h.pump(rounds: 40)
    assert_equal "LOADED", @h.window.document.get_element_by_id("lz")&.text_content
    assert_empty @h.errors, @h.error_report
  end

  # React 18 hooks: useId yields a stable id, useLayoutEffect runs after commit,
  # useTransition drives a deferred state update.
  def test_react_18_hooks
    @h.execute(<<~JS)
      const { createElement: e, useId, useLayoutEffect, useTransition, useState } = React;
      globalThis.__H = () => {
        const id = useId();
        const [v, setV] = useState("");
        const [, startTransition] = useTransition();
        useLayoutEffect(() => { setV("layout"); }, []);
        return e('div', null,
          e('span', { id: 'uid' }, id ? 'has-id' : 'no-id'),
          e('span', { id: 'le' }, v),
          e('button', { id: 'tb', onClick: () => startTransition(() => setV("transitioned")) }, 'go'));
      };
    JS
    render("React.createElement(globalThis.__H)")
    assert_equal "has-id", @h.window.document.get_element_by_id("uid").text_content
    assert_equal "layout", @h.window.document.get_element_by_id("le").text_content

    @h.execute("document.getElementById('tb').click();")
    @h.pump(rounds: 30)
    assert_equal "transitioned", @h.window.document.get_element_by_id("le").text_content
    assert_empty @h.errors, @h.error_report
  end

  # flushSync applies a state update synchronously (no scheduler pump needed).
  def test_flush_sync
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__A = () => { const [n, setN] = useState(0); globalThis.__setN = setN; return e('span', { id: 's' }, String(n)); };
    JS
    render("React.createElement(globalThis.__A)")
    @h.execute("ReactDOM.flushSync(() => globalThis.__setN(42));")
    assert_equal "42", @h.window.document.get_element_by_id("s").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Server-side rendering: renderToString produces HTML from the element tree
  # (a pure computation — no live DOM involved; hooks render their initial state).
  def test_ssr_render_to_string
    skip "React server bundle not vendored" unless File.exist?(REACT_DOM_SERVER)

    @h.load_script(REACT_DOM_SERVER)
    html = @h.evaluate(<<~JS)
      (() => {
        const { createElement: e, useState } = React;
        const App = () => {
          const [n] = useState(7);
          return e('div', { className: 'box' }, e('h1', null, 'Hello SSR'), e('span', null, 'n=' + n));
        };
        return ReactDOMServer.renderToString(e(App));
      })()
    JS
    assert_equal '<div class="box"><h1>Hello SSR</h1><span>n=7</span></div>', html
    assert_empty @h.errors, @h.error_report
  end

  # useSyncExternalStore — the subscription API Redux / Zustand / Jotai build on:
  # a store update outside React re-renders the subscribed component.
  def test_use_sync_external_store
    @h.execute(<<~JS)
      const { createElement: e, useSyncExternalStore } = React;
      let val = 0; const subs = new Set();
      globalThis.__store = {
        get: () => val,
        set: (v) => { val = v; subs.forEach((f) => f()); },
        sub: (f) => { subs.add(f); return () => subs.delete(f); },
      };
      globalThis.__C = () => e('span', { id: 's' }, 'v=' + useSyncExternalStore(globalThis.__store.sub, globalThis.__store.get));
    JS
    render("React.createElement(globalThis.__C)")
    assert_equal "v=0", @h.window.document.get_element_by_id("s").text_content

    @h.execute("globalThis.__store.set(42);")
    @h.pump(rounds: 20)
    assert_equal "v=42", @h.window.document.get_element_by_id("s").text_content
    assert_empty @h.errors, @h.error_report
  end

  # useEffect's cleanup runs when the component unmounts.
  def test_effect_cleanup_on_unmount
    @h.execute(<<~JS)
      const { createElement: e, useEffect, useState } = React;
      globalThis.__log = [];
      const Child = () => {
        useEffect(() => { globalThis.__log.push('mount'); return () => globalThis.__log.push('cleanup'); }, []);
        return e('span', null, 'c');
      };
      globalThis.__P = () => {
        const [show, setShow] = useState(true);
        globalThis.__setShow = setShow;
        return show ? e(Child) : e('span', null, 'gone');
      };
    JS
    render("React.createElement(globalThis.__P)")
    assert_equal ["mount"], @h.evaluate("globalThis.__log")

    @h.execute("globalThis.__setShow(false);")
    @h.pump(rounds: 20)
    assert_equal %w[mount cleanup], @h.evaluate("globalThis.__log")
    assert_empty @h.errors, @h.error_report
  end

  # A Provider value change re-renders its consumers.
  def test_context_value_propagation
    @h.execute(<<~JS)
      const { createElement: e, createContext, useContext, useState } = React;
      const Ctx = createContext(0);
      const Consumer = () => e('span', { id: 'cv' }, 'c=' + useContext(Ctx));
      globalThis.__A = () => { const [v, setV] = useState(1); globalThis.__setV = setV; return e(Ctx.Provider, { value: v }, e(Consumer)); };
    JS
    render("React.createElement(globalThis.__A)")
    assert_equal "c=1", @h.window.document.get_element_by_id("cv").text_content

    @h.execute("globalThis.__setV(9);")
    @h.pump(rounds: 20)
    assert_equal "c=9", @h.window.document.get_element_by_id("cv").text_content
    assert_empty @h.errors, @h.error_report
  end

  # A controlled <textarea> (its value lives in a property, like input/select).
  def test_controlled_textarea
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__T = () => {
        const [v, setV] = useState("hi");
        return e('div', null,
          e('textarea', { id: 'ta', value: v, onChange: (ev) => setV(ev.target.value) }),
          e('span', { id: 'tv' }, v));
      };
    JS
    render("React.createElement(globalThis.__T)")
    assert_equal "hi", @h.window.document.get_element_by_id("tv").text_content

    @h.execute(<<~JS)
      const ta = document.getElementById('ta');
      Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(ta, 'world');
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    assert_equal "world", @h.window.document.get_element_by_id("tv").text_content
    assert_empty @h.errors, @h.error_report
  end

  # A realistic mini app composing state, a controlled input, keyed list
  # reconciliation, immutable updates, conditional filtering, and per-item
  # event handlers — exercising the whole surface end to end.
  def test_todo_app_integration
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__Todo = () => {
        const [items, setItems] = useState([{ id: 1, text: 'first', done: false }]);
        const [text, setText] = useState('');
        const [filter, setFilter] = useState('all');
        const add = () => { if (!text) return; setItems([...items, { id: items.length + 2, text, done: false }]); setText(''); };
        const toggle = (id) => setItems(items.map((i) => i.id === id ? { ...i, done: !i.done } : i));
        const del = (id) => setItems(items.filter((i) => i.id !== id));
        const shown = items.filter((i) => filter === 'all' || (filter === 'done' ? i.done : !i.done));
        return e('div', null,
          e('input', { id: 'newt', value: text, onChange: (ev) => setText(ev.target.value) }),
          e('button', { id: 'add', onClick: add }, 'add'),
          e('button', { id: 'f-active', onClick: () => setFilter('active') }, 'active'),
          e('ul', { id: 'list' }, shown.map((i) => e('li', { key: i.id },
            e('span', { className: i.done ? 'done' : '' }, i.text),
            e('button', { className: 'tog', onClick: () => toggle(i.id) }, 'x'),
            e('button', { className: 'del', onClick: () => del(i.id) }, '-')))),
          e('span', { id: 'count' }, 'count=' + shown.length));
      };
    JS
    render("React.createElement(globalThis.__Todo)")
    assert_equal "count=1", @h.window.document.get_element_by_id("count").text_content

    # Type into the controlled input and add a second item.
    @h.execute(<<~JS)
      const i = document.getElementById('newt');
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(i, 'second');
      i.dispatchEvent(new Event('input', { bubbles: true }));
    JS
    @h.pump(rounds: 20)
    @h.execute("document.getElementById('add').click();")
    @h.pump(rounds: 20)
    assert_equal "count=2", @h.window.document.get_element_by_id("count").text_content

    # Toggle the first item done, then filter to active (hides it).
    @h.execute("document.querySelectorAll('.tog')[0].click();")
    @h.pump(rounds: 20)
    assert_equal "done", @h.window.document.query_selector("#list li span").get_attribute("class")

    @h.execute("document.getElementById('f-active').click();")
    @h.pump(rounds: 20)
    assert_equal "count=1", @h.window.document.get_element_by_id("count").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Hydration: hydrateRoot attaches React to server-rendered markup already in the
  # container — reusing the existing DOM nodes (not re-creating them) and wiring up
  # events so the page becomes interactive.
  def test_hydration
    skip "React server bundle not vendored" unless File.exist?(REACT_DOM_SERVER)

    @h.load_script(REACT_DOM_SERVER)
    # Render to a string and seed the container, as a server response would.
    @h.execute(<<~JS)
      const { createElement: e, useState } = React;
      globalThis.__App = () => {
        const [n, setN] = useState(0);
        return e('div', null,
          e('span', { id: 'count' }, 'n=' + n),
          e('button', { id: 'b', onClick: () => setN(n + 1) }, '+'));
      };
      document.getElementById('root').innerHTML = ReactDOMServer.renderToString(e(globalThis.__App));
      // Hold the server-rendered node so we can prove hydration reuses it (same
      // node identity afterward) rather than replacing it.
      globalThis.__serverNode = document.getElementById('count');
    JS
    assert_equal "n=0", @h.window.document.get_element_by_id("count").text_content

    @h.execute("ReactDOM.hydrateRoot(document.getElementById('root'), React.createElement(globalThis.__App));")
    @h.pump(rounds: 20)
    # The pre-existing node was hydrated in place, not replaced.
    assert_equal true, @h.evaluate("globalThis.__serverNode === document.getElementById('count') && globalThis.__serverNode.isConnected")

    # Events were attached during hydration → the page is interactive.
    @h.execute("document.getElementById('b').click();")
    @h.pump(rounds: 20)
    assert_equal "n=1", @h.window.document.get_element_by_id("count").text_content
    assert_empty @h.errors, @h.error_report
  end
end
