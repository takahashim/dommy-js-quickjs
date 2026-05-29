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
