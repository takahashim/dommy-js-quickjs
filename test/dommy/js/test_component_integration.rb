# frozen_string_literal: true

require "test_helper"

# End-to-end checks that exercise the whole bridge the way a real frontend
# component does: a JS-defined custom element with reactive expando state,
# observed-attribute reflection, innerHTML rendering, scoped querySelector,
# event listeners, and re-rendering — all at once.
class Dommy::Js::TestComponentIntegration < Minitest::Test
  def setup
    @win = Dommy.parse("<div id='app'></div>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.define_host_object("document", @win.document)
    @rt.install_window(@win)
  end

  def teardown
    @rt&.dispose
  end

  def test_reactive_counter_component
    @rt.execute(<<~JS)
      class XCounter extends HTMLElement {
        static get observedAttributes() { return ["count"]; }
        constructor() { super(); this._clicks = 0; }
        connectedCallback() { this.render(); }
        attributeChangedCallback() { this.render(); }
        get count() { return parseInt(this.getAttribute("count") || "0", 10); }
        render() {
          this.innerHTML = `<button class="inc">+</button><span class="val">${this.count}</span>`;
          this.querySelector(".inc").addEventListener("click", () => {
            this._clicks++;
            this.setAttribute("count", String(this.count + 1));
          });
        }
      }
      customElements.define("x-counter", XCounter);
      const el = document.createElement("x-counter");
      el.setAttribute("count", "0");
      document.querySelector("#app").appendChild(el);
    JS

    counter = @win.document.query_selector("x-counter")
    assert_equal "0", counter.query_selector(".val").text_content

    3.times { counter.query_selector(".inc").dispatch_event(Dommy::Event.new("click")) }

    assert_equal "3", counter.query_selector(".val").text_content
    assert_equal "3", counter.get_attribute("count")
    # the expando state survived across re-renders (same backing node/proxy)
    assert_equal 3, @rt.evaluate('document.querySelector("x-counter")._clicks')
  end

  # List rendering: build children from data, then read them back via the live
  # children collection (iteration) from both JS and Ruby.
  def test_list_rendering_component
    @rt.execute(<<~JS)
      class XList extends HTMLElement {
        set items(values) { this._items = values; this.render(); }
        render() {
          this.innerHTML = (this._items || []).map((v) => `<li>${v}</li>`).join("");
        }
      }
      customElements.define("x-list", XList);
      const el = document.createElement("x-list");
      document.querySelector("#app").appendChild(el);
      el.items = ["a", "b", "c"];
      globalThis.__joined = [...el.children].map((li) => li.textContent).join(",");
    JS

    assert_equal "a,b,c", @rt.evaluate("globalThis.__joined")
    list = @win.document.query_selector("x-list")
    assert_equal 3, list.query_selector_all("li").length
  end

  # MutationObserver is constructable as a bare global and its callback fires
  # with real records — the pattern Turbo relies on to detect DOM changes.
  def test_mutation_observer
    @rt.execute(<<~JS)
      globalThis.__records = [];
      const obs = new MutationObserver((records) => {
        for (const r of records) __records.push(r.type + ":" + r.addedNodes.length);
      });
      obs.observe(document.querySelector("#app"), { childList: true });
      document.querySelector("#app").appendChild(document.createElement("p"));
    JS
    @win.scheduler.drain_microtasks
    @rt.drain_microtasks
    assert_equal "childList:1", @rt.evaluate("globalThis.__records.join(',')")
  end
end
