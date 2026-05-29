# frozen_string_literal: true

require "test_helper"

class Dommy::Js::TestQuickjs < Minitest::Test
  def setup
    @win = Dommy.parse(<<~HTML)
      <div id="root">
        <h1 class="title">Products</h1>
        <button class="primary">Click me</button>
      </div>
    HTML
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.define_host_object("document", @win.document)
  end

  def teardown
    @rt&.dispose
  end

  def test_that_it_has_a_version_number
    refute_nil ::Dommy::Js::Quickjs::VERSION
  end

  # property read routes through __js_get__ (and querySelector via __js_call__)
  def test_property_get
    assert_equal "BUTTON", @rt.evaluate('document.querySelector(".primary").tagName')
  end

  def test_text_content_get
    assert_equal "Click me", @rt.evaluate('document.querySelector(".primary").textContent')
  end

  def test_get_attribute_method_call
    assert_equal "title", @rt.evaluate('document.querySelector("h1").getAttribute("class")')
  end

  # property write routes through __js_set__
  def test_property_set_roundtrip
    @rt.execute('document.querySelector("h1").textContent = "Renamed";')
    assert_equal "Renamed", @rt.evaluate('document.querySelector("h1").textContent')
  end

  def test_set_is_visible_to_ruby
    @rt.execute('document.querySelector("h1").textContent = "FromJS";')
    assert_equal "FromJS", @win.document.query_selector("h1").text_content
  end

  # same Ruby node -> same JS proxy
  def test_identity_across_queries
    assert_equal true, @rt.evaluate('document.querySelector("h1") === document.querySelector("h1")')
  end

  # querySelectorAll (NodeList) arrives in JS as an array of child proxies
  def test_query_selector_all_returns_array
    js = 'document.querySelectorAll("h1, .primary").map(n => n.tagName).join(",")'
    assert_equal "H1,BUTTON", @rt.evaluate(js)
  end

  # createElement + appendChild: a host proxy passed back as an argument is
  # unwrapped to the Ruby node, and the mutation is observable from Ruby.
  def test_create_and_append
    @rt.execute(<<~JS)
      const p = document.createElement("p");
      p.textContent = "added from JS";
      document.querySelector("#root").appendChild(p);
    JS
    assert_equal 1, @win.document.query_selector_all("#root p").length
    assert_equal "added from JS", @rt.evaluate('document.querySelector("#root p").textContent')
  end

  # A live JS function (closure intact) is invoked when a Dommy event dispatch
  # reaches it — JS -> Ruby -> JS round trip. `count` surviving across three
  # dispatches proves the same retained function runs, not a re-eval of source.
  # (execute wraps the body in a function, so `count` lives in that closure.)
  def test_event_listener_roundtrip_with_closure
    @rt.execute(<<~JS)
      let count = 0;
      document.querySelector(".primary").addEventListener("click", (e) => {
        count++;
        globalThis.lastResult = count + ":" + e.type;
      });
    JS
    button = @win.document.query_selector(".primary")
    3.times { button.dispatch_event(Dommy::Event.new("click")) }
    assert_equal "3:click", @rt.evaluate("globalThis.lastResult")
  end

  # removeEventListener with the same JS function must detach the listener:
  # same fn -> same id -> same Ruby HostCallback, which Dommy matches by identity.
  def test_remove_event_listener
    @rt.execute(<<~JS)
      globalThis.calls = 0;
      const fn = () => { globalThis.calls += 1; };
      const btn = document.querySelector(".primary");
      btn.addEventListener("click", fn);
      btn.removeEventListener("click", fn);
    JS
    @win.document.query_selector(".primary").dispatch_event(Dommy::Event.new("click"))
    assert_equal 0, @rt.evaluate("globalThis.calls")
  end

  # window injected as a host object; window.document reaches the same DOM.
  def test_window_document_access
    @rt.define_host_object("window", @win)
    assert_equal "BUTTON", @rt.evaluate('window.document.querySelector(".primary").tagName')
  end

  # bare setTimeout routes into Dommy's deterministic scheduler: the JS callback
  # fires only when Ruby advances time.
  def test_set_timeout_uses_dommy_scheduler
    @rt.install_window(@win)
    @rt.execute('globalThis.fired = false; setTimeout(() => { globalThis.fired = true; }, 10);')
    assert_equal false, @rt.evaluate("globalThis.fired")
    @win.scheduler.advance_time(10)
    assert_equal true, @rt.evaluate("globalThis.fired")
  end

  # setInterval also rides Dommy's scheduler: advancing 35ms fires the 10/20/30 ticks.
  def test_set_interval_uses_dommy_scheduler
    @rt.install_window(@win)
    @rt.execute('globalThis.ticks = 0; setInterval(() => { globalThis.ticks += 1; }, 10);')
    @win.scheduler.advance_time(35)
    assert_equal 3, @rt.evaluate("globalThis.ticks")
  end

  # evaluate awaits, so a Promise result resolves to its value.
  def test_evaluate_resolves_promise
    assert_equal 42, @rt.evaluate("Promise.resolve(42)")
  end

  # A DOM node nested inside a returned object is tagged/decoded too (wrap and
  # unwrap are symmetric), so it arrives as a real Dommy element — not the empty
  # Hash a raw proxy would become.
  def test_nested_object_with_node_roundtrip
    result = @rt.evaluate('({ el: document.querySelector("h1"), n: 5 })')
    assert_equal 5, result["n"]
    assert_kind_of ::Dommy::Element, result["el"]
    assert_equal "Products", result["el"].text_content
  end

  # A cyclic object doesn't blow the stack during marshalling; the cycle is cut.
  def test_cyclic_object_does_not_overflow
    result = @rt.evaluate("const o = {}; o.self = o; o.n = 1; return o;")
    assert_equal 1, result["n"]
  end

  # evaluate also accepts a statement body that uses `return`.
  def test_evaluate_statement_with_return
    assert_equal 7, @rt.evaluate("const a = 3; const b = 4; return a + b;")
  end

  # ...and a return that yields a DOM node still decodes to a Dommy element.
  def test_evaluate_statement_returning_node
    result = @rt.evaluate('const h = document.querySelector("h1"); return h;')
    assert_kind_of ::Dommy::Element, result
    assert_equal "Products", result.text_content
  end

  # classList is a bridge object; its methods (manifest) route through __js_call__.
  def test_classlist_add
    @rt.execute('document.querySelector("h1").classList.add("active");')
    assert_includes @win.document.query_selector("h1").get_attribute("class"), "active"
  end

  # style.setProperty reflects to the element's inline style.
  def test_style_set_property
    @rt.execute('document.querySelector("h1").style.setProperty("color", "red");')
    assert_equal "red", @rt.evaluate('document.querySelector("h1").style.getPropertyValue("color")')
  end

  # event methods (preventDefault) are callable inside a listener.
  def test_event_prevent_default
    @rt.execute(<<~JS)
      document.querySelector(".primary").addEventListener("click", (e) => { e.preventDefault(); });
    JS
    ev = Dommy::Event.new("click", "cancelable" => true)
    @win.document.query_selector(".primary").dispatch_event(ev)
    assert_equal true, ev.default_prevented?
  end

  # clearInterval stops further ticks.
  def test_clear_interval
    @rt.install_window(@win)
    @rt.execute('globalThis.t = 0; globalThis.id = setInterval(() => { globalThis.t += 1; }, 10);')
    @win.scheduler.advance_time(10)
    @rt.execute('clearInterval(globalThis.id);')
    @win.scheduler.advance_time(50)
    assert_equal 1, @rt.evaluate("globalThis.t")
  end

  # requestAnimationFrame callback fires on advance.
  def test_request_animation_frame
    @rt.install_window(@win)
    @rt.execute('globalThis.raf = false; requestAnimationFrame(() => { globalThis.raf = true; });')
    @win.scheduler.advance_time(16)
    assert_equal true, @rt.evaluate("globalThis.raf")
  end

  # 1a: interface metadata is exposed to JS via __rbHost.interfaceOf. An element
  # reports its full DOM interface chain, most-derived first, up to EventTarget.
  def test_interface_chain_for_element
    js = '__rbHost.interfaceOf(document.querySelector(".primary")).chain.join(",")'
    assert_equal "HTMLButtonElement,HTMLElement,Element,Node,EventTarget", @rt.evaluate(js)
  end

  def test_interface_name_is_most_derived
    assert_equal "HTMLHeadingElement", @rt.evaluate('__rbHost.interfaceOf(document.querySelector("h1")).name')
  end

  # Dommy's class names (TextNode/CommentNode/CharacterDataNode/Fragment) are
  # mapped to the WebIDL interface names (Text/Comment/CharacterData/
  # DocumentFragment) via INTERFACE_NAME_OVERRIDES.
  def test_interface_chain_for_text_node
    js = 'return __rbHost.interfaceOf(document.createTextNode("hi")).chain.join(",");'
    assert_equal "Text,CharacterData,Node,EventTarget", @rt.evaluate(js)
  end

  def test_interface_chain_for_comment_node
    js = 'return __rbHost.interfaceOf(document.createComment("x")).chain.join(",");'
    assert_equal "Comment,CharacterData,Node,EventTarget", @rt.evaluate(js)
  end

  def test_interface_chain_for_document_fragment
    js = 'return __rbHost.interfaceOf(document.createDocumentFragment()).chain.join(",");'
    assert_equal "DocumentFragment,Node,EventTarget", @rt.evaluate(js)
  end

  # The document itself: Document -> Node -> EventTarget.
  def test_interface_chain_for_document
    @rt.define_host_object("window", @win)
    assert_equal "Document,Node,EventTarget",
      @rt.evaluate("__rbHost.interfaceOf(window.document).chain.join(\",\")")
  end

  # interfaceOf on a plain (non-host) JS object is null — it only describes proxies.
  def test_interface_of_non_proxy_is_null
    assert_nil @rt.evaluate("__rbHost.interfaceOf({})")
  end

  # 1b: nodes are now real instances of their DOM interface constructors, with
  # the full inheritance chain reachable via instanceof.
  def test_instanceof_full_chain
    js = <<~JS
      const b = document.querySelector(".primary");
      return [
        b instanceof HTMLButtonElement,
        b instanceof HTMLElement,
        b instanceof Element,
        b instanceof Node,
        b instanceof EventTarget
      ].join(",");
    JS
    assert_equal "true,true,true,true,true", @rt.evaluate(js)
  end

  # A button is not a Text node — sibling interfaces don't share a subtree.
  def test_instanceof_negative
    assert_equal false, @rt.evaluate('document.querySelector(".primary") instanceof Text')
  end

  # Text nodes climb Text -> CharacterData -> Node but are not Elements.
  def test_instanceof_text_node
    js = <<~JS
      const t = document.createTextNode("hi");
      return [t instanceof Text, t instanceof CharacterData, t instanceof Node, t instanceof Element].join(",");
    JS
    assert_equal "true,true,true,false", @rt.evaluate(js)
  end

  # Symbol.toStringTag flows from the interface prototype, so the brand string
  # is the interface name (what testharness.js's assert_class_string checks).
  def test_to_string_tag
    assert_equal "[object HTMLHeadingElement]",
      @rt.evaluate('Object.prototype.toString.call(document.querySelector("h1"))')
  end

  def test_constructor_name
    assert_equal "HTMLButtonElement", @rt.evaluate('document.querySelector(".primary").constructor.name')
  end

  # Interface constructors exist as globals but are not directly constructable.
  def test_interface_constructor_is_illegal
    assert_equal "function", @rt.evaluate("typeof HTMLElement")
    assert_equal true, @rt.evaluate(<<~JS)
      try { new HTMLElement(); return false; } catch (e) { return e instanceof TypeError; }
    JS
  end

  # Bridge sub-objects get their WebIDL interface names too.
  def test_classlist_interface_name
    assert_equal "DOMTokenList",
      @rt.evaluate('document.querySelector("h1").classList[Symbol.toStringTag]')
  end

  # 1c: events can be constructed from JS with `new`, producing a real Dommy
  # event reachable through the ABI and instanceof the right interfaces.
  def test_new_custom_event
    @rt.install_window(@win)
    js = <<~JS
      const e = new CustomEvent("greet", { detail: 42 });
      return [e instanceof CustomEvent, e instanceof Event, e.type, e.detail].join(",");
    JS
    assert_equal "true,true,greet,42", @rt.evaluate(js)
  end

  def test_new_event_with_init
    @rt.install_window(@win)
    js = 'const e = new Event("x", { bubbles: true }); return [e instanceof Event, e.type, e.bubbles].join(",");'
    assert_equal "true,x,true", @rt.evaluate(js)
  end

  # A JS-constructed event dispatches through Dommy to a JS listener: the same
  # event instance arrives, carrying its detail.
  def test_dispatch_js_constructed_event
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      const btn = document.querySelector(".primary");
      btn.addEventListener("greet", (e) => { globalThis.got = e.detail; });
      btn.dispatchEvent(new CustomEvent("greet", { detail: "hi" }));
    JS
    assert_equal "hi", @rt.evaluate("globalThis.got")
  end

  # DOMException isn't on the window but is still constructable, and is a proper
  # JS error type (what testharness.js's assert_throws_dom relies on).
  def test_new_dom_exception
    js = <<~JS
      const e = new DOMException("nope", "NotFoundError");
      return [e instanceof DOMException, e.name, e.message, e.code].join(",");
    JS
    assert_equal "true,NotFoundError,nope,8", @rt.evaluate(js)
  end

  # 1d: a JS `class extends HTMLElement` registered via customElements.define is
  # upgraded onto a Dommy node. createElement yields an instance of the JS class
  # (and of HTMLElement) — the construction-stack adoption end to end.
  def test_custom_element_create_is_instance
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      globalThis.MyEl = class extends HTMLElement {};
      customElements.define("my-el", MyEl);
    JS
    assert_equal true, @rt.evaluate('document.createElement("my-el") instanceof MyEl')
    assert_equal true, @rt.evaluate('document.createElement("my-el") instanceof HTMLElement')
    assert_equal "MY-EL", @rt.evaluate('document.createElement("my-el").tagName')
  end

  # connectedCallback fires when the element is attached, with `this` bound to the
  # Dommy-backed node, so its DOM writes are visible from Ruby.
  def test_custom_element_connected_callback
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      class MyEl extends HTMLElement {
        connectedCallback() { this.textContent = "UP"; }
      }
      customElements.define("my-el", MyEl);
      document.querySelector("#root").appendChild(document.createElement("my-el"));
    JS
    assert_equal "UP", @win.document.query_selector("my-el").text_content
  end

  # attributeChangedCallback fires for observed attributes after the constructor.
  def test_custom_element_attribute_changed_callback
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      class MyEl extends HTMLElement {
        static get observedAttributes() { return ["data-x"]; }
        attributeChangedCallback(name, oldV, newV) { this.textContent = name + "=" + newV; }
      }
      customElements.define("my-el", MyEl);
      const el = document.createElement("my-el");
      document.querySelector("#root").appendChild(el);
      el.setAttribute("data-x", "42");
    JS
    assert_equal "data-x=42", @win.document.query_selector("my-el").text_content
  end

  # An element already present in the parsed document is upgraded retroactively
  # when its definition lands later (Dommy's upgrade_existing → JS construct +
  # connectedCallback). No define-before-parse restriction needed.
  def test_custom_element_upgrades_existing_node
    win = Dommy.parse("<div id='host'><my-el></my-el></div>")
    rt = Dommy::Js::Quickjs::Runtime.new
    rt.install_window(win)
    rt.execute(<<~JS)
      globalThis.MyEl = class extends HTMLElement {
        connectedCallback() { this.textContent = "upgraded"; }
      };
      customElements.define("my-el", MyEl);
    JS
    assert_equal "upgraded", win.document.query_selector("my-el").text_content
  ensure
    rt&.dispose
  end

  # customElements.whenDefined stays pending until the name is defined, then
  # resolves with the constructor (not an early resolve with undefined).
  def test_custom_element_when_defined_pending
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      globalThis.__seen = "none";
      customElements.whenDefined("x-late").then((c) => { globalThis.__seen = (c === globalThis.XLate) ? "ctor" : "other"; });
      globalThis.XLate = class extends HTMLElement {};
      customElements.define("x-late", XLate);
    JS
    assert_equal "ctor", @rt.evaluate("globalThis.__seen")
  end

  # customElements.upgrade delegates to Dommy's registry without error.
  def test_custom_element_upgrade_delegates
    @rt.install_window(@win)
    assert_equal "ok", @rt.evaluate(<<~JS)
      customElements.define("x-up", class extends HTMLElement {});
      customElements.upgrade(document.querySelector("#root"));
      return "ok";
    JS
  end

  # customElements.get returns the registered constructor.
  def test_custom_element_registry_get
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      globalThis.MyEl = class extends HTMLElement {};
      customElements.define("my-el", MyEl);
    JS
    assert_equal true, @rt.evaluate('customElements.get("my-el") === MyEl')
  end

  # 2b: a node's sub-objects keep a stable identity across reads (Dommy returns
  # the same Ruby object; the handle cache maps it to one proxy).
  def test_sub_object_identity
    js = 'const e = document.querySelector("#root"); return e.classList === e.classList && e.style === e.style;'
    assert_equal true, @rt.evaluate(js)
  end

  # 2a: an HTMLCollection (el.children) crosses as an array-like proxy and is now
  # iterable — for-of and spread work, not just indexed access.
  def test_html_collection_is_iterable
    @win.document.query_selector("#root").inner_html = "<h1>A</h1><p>B</p>"
    js = <<~JS
      const kids = document.querySelector("#root").children;
      const out = [];
      for (const c of kids) out.push(c.tagName);
      return out.join(",") + "|" + [...kids].length;
    JS
    assert_equal "H1,P|2", @rt.evaluate(js)
  end

  # querySelectorAll already crosses as a real array (Dommy::NodeList < Array).
  def test_query_selector_all_array_methods
    @win.document.query_selector("#root").inner_html = "<h1>A</h1><p>B</p>"
    assert_equal "H1,P",
      @rt.evaluate('document.querySelectorAll("#root *").map(n => n.tagName).join(",")')
  end

  # (A) Node traversal is exposed: childNodes (live), firstChild, siblings.
  def test_node_traversal
    @win.document.query_selector("#root").inner_html = "<h1>A</h1>txt<!--c-->"
    js = <<~JS
      const root = document.querySelector("#root");
      const types = [];
      for (const n of root.childNodes) types.push(n.nodeType);
      return [root.childNodes.length, types.join(""), root.firstChild.tagName,
              document.querySelector("h1").nextSibling.nodeType].join("|");
    JS
    assert_equal "3|138|H1|3", @rt.evaluate(js)
  end

  # childNodes is a live NodeList: same object across reads, reflects mutation.
  def test_child_nodes_live
    root = @win.document.query_selector("#root")
    root.inner_html = "<a></a>"
    assert_equal true,
      @rt.evaluate('document.querySelector("#root").childNodes === document.querySelector("#root").childNodes')
    assert_equal 1, @rt.evaluate('document.querySelector("#root").childNodes.length')
    root.append_child(@win.document.create_element("b"))
    assert_equal 2, @rt.evaluate('document.querySelector("#root").childNodes.length')
  end

  # (B) A non-DOM property set on a node is kept as a JS-side expando, with
  # object identity preserved — while real DOM properties still hit the DOM.
  def test_expando_properties
    js = <<~JS
      const e = document.querySelector("h1");
      e.count = 42;
      e.obj = { nested: true };
      e.id = "real";                 // a real DOM property
      return [e.count, e.obj === e.obj, e.obj.nested, e.id, e.getAttribute("id")].join(",");
    JS
    assert_equal "42,true,true,real,real", @rt.evaluate(js)
  end

  # A class instance stored as a field keeps its methods (identity, not a copy).
  def test_expando_instance_keeps_methods
    js = <<~JS
      class Ctrl { greet() { return "hi"; } }
      const e = document.querySelector("h1");
      e._ctrl = new Ctrl();
      return e._ctrl.greet();
    JS
    assert_equal "hi", @rt.evaluate(js)
  end

  # (B) A framework-style reactive property (setter on the class prototype) runs
  # instead of being swallowed by the DOM ABI.
  def test_prototype_setter_wins
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      globalThis.XLit = class extends HTMLElement {
        set label(v) { this._label = v; this.setAttribute("data-label", v); }
        get label() { return this._label; }
      };
      customElements.define("x-lit", XLit);
      const el = document.createElement("x-lit");
      el.label = "hello";
      globalThis.__r = [el.label, el.getAttribute("data-label")].join(",");
    JS
    assert_equal "hello,hello", @rt.evaluate("globalThis.__r")
  end

  # 2c: a method reference is stable for a given node (memoized per proxy), so
  # identity comparisons frameworks sometimes make hold while you hold the node.
  def test_method_identity
    assert_equal true, @rt.evaluate('const e = document.querySelector("h1"); return e.getAttribute === e.getAttribute;')
  end

  # A function nested in an object (e.g. an event's detail) survives the round
  # trip through Ruby and comes back callable — what Turbo's stream rendering
  # (event.detail.render) relies on.
  def test_function_in_event_detail_round_trips
    @rt.install_window(@win)
    @rt.execute(<<~JS)
      globalThis.__r = "none";
      document.addEventListener("ping", (e) => { globalThis.__r = (typeof e.detail.cb) + ":" + e.detail.cb(21); });
      document.dispatchEvent(new CustomEvent("ping", { detail: { cb: (n) => n * 2 } }));
    JS
    assert_equal "function:42", @rt.evaluate("globalThis.__r")
  end

  # Method-only host objects (no __js_get__ properties to call them out) are now
  # bridged and their methods are callable — previously these silently returned
  # non-functions because the objects lacked __js_method_names__.
  def test_history_pushstate
    @rt.install_window(@win)
    assert_equal "/x",
      @rt.evaluate('window.history.pushState({}, "", "/x"); return window.location.pathname;')
  end

  def test_storage_methods
    @rt.install_window(@win)
    assert_equal "v",
      @rt.evaluate('window.localStorage.setItem("k", "v"); return window.localStorage.getItem("k");')
  end

  def test_form_data_construct_and_use
    @rt.install_window(@win)
    assert_equal "1", @rt.evaluate('const f = new FormData(); f.append("a", "1"); return f.get("a");')
  end

  def test_html_collection_item_method
    @win.document.query_selector("#root").inner_html = "<i>x</i><i>y</i>"
    assert_equal "y", @rt.evaluate('document.querySelector("#root").children.item(1).textContent')
  end

  def test_url_construct
    @rt.install_window(@win)
    assert_equal "/p", @rt.evaluate('new URL("https://e.com/p?q=1").pathname')
  end

  # Handles for transient proxies are released after GC, so the registry stays
  # bounded on a long-lived VM. Each queried <p> crosses to Ruby but is not
  # retained on the JS side, so it becomes collectable.
  def test_handles_released_after_gc
    @win.document.body.inner_html = "<p>a</p>" * 20 + @win.document.body.inner_html
    base = @rt.registered_count
    20.times { |i| @rt.execute("document.querySelectorAll('p')[#{i}].textContent;") }
    grew = @rt.registered_count
    assert_operator grew, :>, base, "querying nodes should register handles"

    @rt.collect_garbage
    assert_operator @rt.registered_count, :<, grew, "GC should release transient handles"
  end
end
