# frozen_string_literal: true

require "test_helper"
require "quickjs"
require "json"

# Unit tests for the pure-JS bridge runtime (lib/dommy/js/host_runtime.js),
# exercised in a bare QuickJS VM with the Ruby `__rb_*` host functions replaced
# by JS stubs backed by an in-memory fake host. No Dommy involved — this isolates
# the JS marshalling/prototype/proxy logic so its edge cases (cycle breaking,
# callback identity, instanceof chains, Illegal constructor) are covered directly.
class Dommy::Js::TestHostRuntime < Minitest::Test
  # Fake host: handle 1 is a button-like node; __rb_construct mints CustomEvents.
  FAKE_HOST_JS = <<~'JS'
    globalThis.__fakeHost = {
      next: 100,
      released: [],
      nodes: {
        1: {
          iface: { name: "HTMLButtonElement",
                   chain: ["HTMLButtonElement", "HTMLElement", "Element", "Node", "EventTarget"] },
          methods: ["getAttribute"],
          props: { tagName: "BUTTON", textContent: "Click" },
          calls: { getAttribute: (args) => "cls:" + args[0] }
        }
      }
    };
    globalThis.__rb_host_interface = (h) => __fakeHost.nodes[h].iface;
    globalThis.__rb_host_methods = (h) => __fakeHost.nodes[h].methods;
    globalThis.__rb_host_get = (h, prop) => {
      // own props only — like Dommy's __js_get__, which returns nil for
      // non-DOM names (constructor, toString, …) rather than leaking
      // Object.prototype members.
      const props = __fakeHost.nodes[h].props;
      return Object.hasOwn(props, prop) ? props[prop] : null;
    };
    globalThis.__rb_host_set = (h, prop, val) => { __fakeHost.nodes[h].props[prop] = val; };
    globalThis.__rb_host_call = (h, m, args) => {
      const fn = __fakeHost.nodes[h].calls[m];
      return fn ? fn(args) : null;
    };
    globalThis.__rb_release_handle = (h) => { __fakeHost.released.push(h); };
    globalThis.__rb_construct = (name, args) => {
      if (name !== "CustomEvent") return null;            // others "not constructable"
      const h = __fakeHost.next++;
      __fakeHost.nodes[h] = {
        iface: { name: "CustomEvent", chain: ["CustomEvent", "Event"] },
        methods: [], calls: {},
        props: { type: args[0], detail: (args[1] || {}).detail }
      };
      return { __rb_handle: h };
    };
  JS

  def setup
    @vm = Quickjs::VM.new(timeout_msec: 60_000)
    @vm.eval_code(FAKE_HOST_JS, async: false)
    @vm.eval_code(Dommy::Js::HostBridge::HOST_RUNTIME_JS, async: false)
    @vm.eval_code("__rbHost.seedInterfaces(#{JSON.generate(Dommy::Js::DomInterfaces::BASE_CHAINS)});", async: false)
  end

  def teardown
    @vm&.dispose!
  end

  # Evaluate a JS expression body (uses `return`) and hand back the value.
  def js(body)
    @vm.eval_code("(function () {\n#{body}\n})()", async: false)
  end

  # --- seedInterfaces / protoForChain ---

  def test_base_interfaces_are_seeded
    assert_equal "function", js('return typeof HTMLElement;')
    assert_equal "function", js('return typeof Node;')
    assert_equal "function", js('return typeof DOMException;')
  end

  def test_shared_prototype_tail
    # Distinct interfaces link into the same parent prototype object.
    assert_equal true, js("return Object.getPrototypeOf(MouseEvent.prototype) === Event.prototype;")
  end

  def test_interface_constructor_name_and_tostringtag
    assert_equal "HTMLElement", js("return HTMLElement.name;")
    assert_equal "Event", js('return Event.prototype[Symbol.toStringTag];')
  end

  # --- makeProxy: get/set/methods/identity ---

  def test_proxy_property_get
    assert_equal "BUTTON", js("return __rbHost.makeProxy(1).tagName;")
  end

  def test_proxy_method_dispatch
    assert_equal "cls:x", js('return __rbHost.makeProxy(1).getAttribute("x");')
  end

  def test_proxy_set_roundtrip
    assert_equal "new", js('const p = __rbHost.makeProxy(1); p.textContent = "new"; return p.textContent;')
  end

  def test_proxy_identity
    assert_equal true, js("return __rbHost.makeProxy(1) === __rbHost.makeProxy(1);")
  end

  # --- instanceof / toStringTag / constructor on a real proxy ---

  def test_proxy_instanceof_chain
    js_body = <<~JS
      const b = __rbHost.makeProxy(1);
      return [b instanceof HTMLButtonElement, b instanceof HTMLElement,
              b instanceof Element, b instanceof Node, b instanceof EventTarget].join(",");
    JS
    assert_equal "true,true,true,true,true", js(js_body)
  end

  def test_proxy_brand_string
    assert_equal "[object HTMLButtonElement]",
      js("return Object.prototype.toString.call(__rbHost.makeProxy(1));")
  end

  # `.constructor` isn't a DOM property; the get trap falls back to the prototype.
  def test_proxy_constructor_falls_back_to_prototype
    assert_equal true, js("return __rbHost.makeProxy(1).constructor === HTMLButtonElement;")
  end

  # --- isProxy / interfaceOf ---

  def test_interface_of_proxy
    assert_equal "HTMLButtonElement", js("return __rbHost.interfaceOf(__rbHost.makeProxy(1)).name;")
  end

  def test_interface_of_non_proxy_is_null
    assert_nil js("return __rbHost.interfaceOf({});")
  end

  # --- dehydrate (tag): cycles, functions, proxies ---

  def test_tag_breaks_cycles
    assert_equal 1, js("const o = {}; o.self = o; o.n = 1; return __rbHost.tag(o).n;")
    # the cycle is cut to JS undefined (QuickJS surfaces that as :undefined)
    assert_equal "undefined", js("const o = {}; o.self = o; return typeof __rbHost.tag(o).self;")
  end

  def test_tag_functions_become_callback_refs
    assert_equal "number", js("return typeof __rbHost.tag(() => {}).__rb_callback;")
  end

  def test_tag_proxy_becomes_handle_ref
    assert_equal 1, js("return __rbHost.tag(__rbHost.makeProxy(1)).__rb_handle;")
  end

  # --- callback identity + invocation ---

  def test_same_function_same_callback_id
    assert_equal true, js("const f = () => 9; return __rbHost.tag(f).__rb_callback === __rbHost.tag(f).__rb_callback;")
  end

  def test_invoke_callback_round_trip
    js_body = <<~JS
      const id = __rbHost.tag((a) => a + 1).__rb_callback;
      return __rbHost.invokeCallback(id, [41]);
    JS
    assert_equal 42, js(js_body)
  end

  # --- constructInterface (new Foo) ---

  def test_construct_custom_event
    js_body = <<~JS
      const e = new CustomEvent("greet", { detail: 5 });
      return [e instanceof CustomEvent, e instanceof Event, e.type, e.detail].join(",");
    JS
    assert_equal "true,true,greet,5", js(js_body)
  end

  def test_non_constructable_throws_illegal_constructor
    js_body = <<~JS
      try { new HTMLElement(); return "no-throw"; }
      catch (e) { return e instanceof TypeError ? e.message : "wrong-type"; }
    JS
    assert_equal "Illegal constructor", js(js_body)
  end

  def test_constructor_requires_new
    js_body = <<~JS
      try { Event("x"); return "no-throw"; }
      catch (e) { return e.message; }
    JS
    assert_equal "Event requires 'new'", js(js_body)
  end
end
