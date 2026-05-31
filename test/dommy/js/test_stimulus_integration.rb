# frozen_string_literal: true

require "test_helper"

# Drives the *real* @hotwired/stimulus UMD bundle on Dommy + QuickJS. Stimulus
# binds its action listeners with the EventListener *object* form
# (`el.addEventListener(type, this)` where `this` has a `handleEvent` method),
# so this is the end-to-end proof the bridge supports that form. Skips unless
# the bundle is vendored at test/fixtures/stimulus.umd.js (fetch it with:
#   curl -sL https://unpkg.com/@hotwired/stimulus@3/dist/stimulus.umd.js \
#     -o test/fixtures/stimulus.umd.js
# ).
class Dommy::Js::TestStimulusIntegration < Minitest::Test
  BUNDLE = File.expand_path("../../fixtures/stimulus.umd.js", __dir__)

  def setup
    skip "Stimulus bundle not vendored (#{BUNDLE})" unless File.exist?(BUNDLE)
  end

  def teardown
    @h&.dispose
  end

  # Build the harness around `html`, boot a Stimulus Application, and register
  # `controllers` (a Hash of identifier => JS class body). Pumps so connect()
  # and the initial MutationObserver scan land.
  def boot(html, controllers)
    @h = Dommy::Js::BrowserHarness.new(html)
    @h.load_script(BUNDLE)
    regs = controllers.map do |ident, body|
      "globalThis.__app.register(#{ident.inspect}, #{body});"
    end.join("\n")
    @h.execute(<<~JS)
      const { Application, Controller } = Stimulus;
      globalThis.Controller = Controller;
      globalThis.__app = Application.start();
      #{regs}
    JS
    @h.pump(rounds: 20)
    @h
  end

  def controller_for(id, identifier)
    "globalThis.__app.getControllerForElementAndIdentifier(document.getElementById(#{id.inspect}), #{identifier.inspect})"
  end

  def test_stimulus_loads
    boot("<!DOCTYPE html><html><head></head><body></body></html>", {})
    assert_equal "object", @h.evaluate("typeof Stimulus")
    assert_equal "function", @h.evaluate("typeof Stimulus.Application")
    assert_empty @h.errors, @h.error_report
  end

  # connect() fires on the controller element and targets resolve.
  def test_controller_connect_and_targets
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='hello'><span data-hello-target='out'></span></div></body></html>",
      "hello" => <<~JS
        class extends Controller {
          static targets = ["out"];
          connect() { this.outTarget.textContent = "connected"; }
        }
      JS
    )
    assert_equal "connected", @h.window.document.query_selector("[data-hello-target=out]").text_content
    assert_empty @h.errors, @h.error_report
  end

  # An action (`click->c#m`) is bound via the EventListener-object form; a click
  # invokes the controller method. This is the path the handleEvent support
  # unlocks.
  def test_action_fires_on_click
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='c'>" \
      "<button id='b' data-action='click->c#go'>go</button>" \
      "<span id='out'></span></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          go() { document.getElementById("out").textContent = "clicked"; }
        }
      JS
    )
    @h.execute('document.getElementById("b").click();')
    @h.pump(rounds: 10)
    assert_equal "clicked", @h.window.document.get_element_by_id("out").text_content
    assert_empty @h.errors, @h.error_report
  end

  # Keyboard action filters (`keydown.enter->c#m`) match only the named key.
  def test_action_keyboard_filter
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='c'><input id='f' data-action='keydown.enter->c#submit'></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          submit() { globalThis.__submits = (globalThis.__submits || 0) + 1; }
        }
      JS
    )
    @h.execute('document.getElementById("f").dispatchEvent(new KeyboardEvent("keydown", { key: "a", bubbles: true }));')
    @h.pump(rounds: 5)
    assert_equal 0, @h.evaluate("globalThis.__submits || 0")

    @h.execute('document.getElementById("f").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));')
    @h.pump(rounds: 5)
    assert_equal 1, @h.evaluate("globalThis.__submits || 0")
    assert_empty @h.errors, @h.error_report
  end

  # Typed values are read from data-*-value attributes, *-Changed callbacks fire,
  # and a value write reflects back to the attribute.
  def test_values_and_value_changed
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='c' data-c-count-value='2'><span id='out'></span></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          static values = { count: Number };
          connect() { this.render(); }
          countValueChanged(v) { globalThis.__changed = v; this.render(); }
          bump() { this.countValue++; }
          render() { document.getElementById("out").textContent = "n=" + this.countValue; }
        }
      JS
    )
    assert_equal "n=2", @h.window.document.get_element_by_id("out").text_content
    assert_equal 2, @h.evaluate("globalThis.__changed")

    @h.execute("#{controller_for('root', 'c')}.bump();")
    @h.pump(rounds: 10)
    assert_equal "n=3", @h.window.document.get_element_by_id("out").text_content
    assert_equal "3", @h.window.document.get_element_by_id("root").get_attribute("data-c-count-value")
    assert_empty @h.errors, @h.error_report
  end

  # CSS classes from data-*-class are exposed as `xClass` and applied.
  def test_classes
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='c' data-c-active-class='is-active'></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          static classes = ["active"];
          activate() { this.element.classList.add(this.activeClass); }
        }
      JS
    )
    @h.execute("#{controller_for('root', 'c')}.activate();")
    @h.pump(rounds: 5)
    assert_equal "is-active", @h.window.document.get_element_by_id("root").get_attribute("class")
    assert_empty @h.errors, @h.error_report
  end

  # dispatch() emits a prefixed CustomEvent whose detail crosses to a listener.
  def test_dispatch_custom_event
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='c'></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          fire() { this.dispatch("ping", { detail: { x: 42 } }); }
        }
      JS
    )
    @h.execute(<<~JS)
      globalThis.__detail = null;
      document.addEventListener("c:ping", (e) => { globalThis.__detail = e.detail.x; });
      #{controller_for("root", "c")}.fire();
    JS
    @h.pump(rounds: 5)
    assert_equal 42, @h.evaluate("globalThis.__detail")
    assert_empty @h.errors, @h.error_report
  end

  # Target connect/disconnect callbacks fire as matching elements enter/leave the
  # controller's subtree (driven by the MutationObserver).
  def test_target_connected_disconnected_callbacks
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='c'><i id='one' data-c-target='item'>1</i></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          static targets = ["item"];
          itemTargetConnected(el) { (globalThis.__conn = globalThis.__conn || []).push(el.textContent); }
          itemTargetDisconnected(el) { (globalThis.__disc = globalThis.__disc || []).push(el.textContent); }
        }
      JS
    )
    assert_equal ["1"], @h.evaluate("globalThis.__conn")

    @h.execute(<<~JS)
      const el = document.createElement("i");
      el.setAttribute("data-c-target", "item");
      el.textContent = "2";
      document.getElementById("root").appendChild(el);
    JS
    @h.pump(rounds: 10)
    assert_equal %w[1 2], @h.evaluate("globalThis.__conn")

    @h.execute('document.getElementById("one").remove();')
    @h.pump(rounds: 10)
    assert_equal ["1"], @h.evaluate("globalThis.__disc")
    assert_empty @h.errors, @h.error_report
  end

  # Outlets connect the controller to other controllers' elements by selector,
  # exposing their controller instances + firing outlet callbacks.
  def test_outlets
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='list' data-list-thing-outlet='.thing'></div>" \
      "<div class='thing' data-controller='thing'><b>A</b></div>" \
      "<div class='thing' data-controller='thing'><b>B</b></div></body></html>",
      "thing" => <<~JS,
        class extends Controller { label() { return this.element.querySelector("b").textContent; } }
      JS
      "list" => <<~JS
        class extends Controller {
          static outlets = ["thing"];
          thingOutletConnected(outlet) { (globalThis.__out = globalThis.__out || []).push(outlet.label()); }
          labels() { return this.thingOutlets.map((o) => o.label()).join(","); }
        }
      JS
    )
    assert_equal %w[A B], @h.evaluate("globalThis.__out")
    assert_equal "A,B", @h.evaluate("#{controller_for('root', 'list')}.labels()")
    assert_empty @h.errors, @h.error_report
  end

  # An outlet element leaving the DOM fires the *Disconnected callback. Stimulus
  # checks the removed element with `element.matches(outletSelector)`, so this
  # exercises matches() on a *detached* node.
  def test_outlet_disconnected
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='list' data-list-thing-outlet='.thing'></div>" \
      "<div id='t1' class='thing' data-controller='thing'><b>A</b></div></body></html>",
      "thing" => <<~JS,
        class extends Controller { label() { return this.element.querySelector("b").textContent; } }
      JS
      "list" => <<~JS
        class extends Controller {
          static outlets = ["thing"];
          thingOutletDisconnected() { (globalThis.__gone = globalThis.__gone || []).push("gone"); }
        }
      JS
    )
    @h.execute('document.getElementById("t1").remove();')
    @h.pump(rounds: 10)
    assert_equal ["gone"], @h.evaluate("globalThis.__gone || []")
    assert_empty @h.errors, @h.error_report
  end

  # Action options: `:stop` (stopPropagation halts a parent action), `:prevent`
  # (preventDefault), `:once` (fires at most once), `:self` (only when the event
  # target is the bound element).
  def test_action_options
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='o' data-action='click->o#outer'>" \
      "<button id='stop' data-action='click->o#inner:stop'>s</button>" \
      "<a id='prev' href='#' data-action='click->o#prev:prevent'>p</a>" \
      "<button id='once' data-action='click->o#onceFn:once'>o</button>" \
      "<div id='outer' data-action='click->o#selfOnly:self'><span id='inner'>i</span></div>" \
      "</div></body></html>",
      "o" => <<~JS
        class extends Controller {
          outer() { globalThis.__outer = (globalThis.__outer || 0) + 1; }
          inner() { globalThis.__inner = (globalThis.__inner || 0) + 1; }
          prev(e) { globalThis.__prevented = e.defaultPrevented; }
          onceFn() { globalThis.__once = (globalThis.__once || 0) + 1; }
          selfOnly() { globalThis.__self = (globalThis.__self || 0) + 1; }
        }
      JS
    )
    # :stop — clicking the stop button runs its action but the click must NOT
    # bubble up to the controller-div's `outer` action. Checked in isolation so
    # nothing else has bubbled to `outer` yet.
    @h.execute('document.getElementById("stop").click();')
    @h.pump(rounds: 5)
    assert_equal 1, @h.evaluate("globalThis.__inner || 0")
    assert_equal 0, @h.evaluate("globalThis.__outer || 0"), ":stop should halt the parent action"

    # The remaining options (these clicks legitimately bubble to `outer`).
    @h.execute('document.getElementById("prev").click();')   # :prevent → defaultPrevented
    @h.execute('document.getElementById("once").click(); document.getElementById("once").click();')
    @h.execute('document.getElementById("inner").click(); document.getElementById("outer").click();')
    @h.pump(rounds: 10)
    assert_equal true, @h.evaluate("globalThis.__prevented")
    assert_equal 1, @h.evaluate("globalThis.__once || 0"), ":once should fire at most once"
    assert_equal 1, @h.evaluate("globalThis.__self || 0"), ":self ignores events from descendants"
    assert_empty @h.errors, @h.error_report
  end

  # Action params: data-c-<name>-param attributes surface as `event.params`.
  def test_action_params
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='p'>" \
      "<button id='b' data-action='p#go' data-p-id-param='42' data-p-name-param='hi'>go</button></div></body></html>",
      "p" => <<~JS
        class extends Controller { go(e) { globalThis.__params = e.params; } }
      JS
    )
    @h.execute('document.getElementById("b").click();')
    @h.pump(rounds: 5)
    assert_equal 42, @h.evaluate("globalThis.__params.id")
    assert_equal "hi", @h.evaluate("globalThis.__params.name")
    assert_empty @h.errors, @h.error_report
  end

  # Value types are coerced from the attribute (Boolean/Array/Object) and a
  # declared default applies when the attribute is absent.
  def test_value_types_and_defaults
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='v' data-v-on-value='true' " \
      "data-v-tags-value='[\"a\",\"b\"]' data-v-cfg-value='{\"k\":1}'></div></body></html>",
      "v" => <<~JS
        class extends Controller {
          static values = { on: Boolean, tags: Array, cfg: Object, miss: { type: String, default: "D" } };
          connect() {
            globalThis.__on = this.onValue;
            globalThis.__tags = this.tagsValue;
            globalThis.__cfg = this.cfgValue;
            globalThis.__miss = this.missValue;
          }
        }
      JS
    )
    assert_equal true, @h.evaluate("globalThis.__on")
    assert_equal %w[a b], @h.evaluate("globalThis.__tags")
    assert_equal 1, @h.evaluate("globalThis.__cfg.k")
    assert_equal "D", @h.evaluate("globalThis.__miss")
    assert_empty @h.errors, @h.error_report
  end

  # Global event targets: `event@window` / `event@document` bind the action to
  # window/document rather than the element.
  def test_global_event_target_actions
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='g' data-action='resize@window->g#onResize keydown@document->g#onKey'></div></body></html>",
      "g" => <<~JS
        class extends Controller {
          onResize() { globalThis.__resized = (globalThis.__resized || 0) + 1; }
          onKey(e) { globalThis.__key = e.key; }
        }
      JS
    )
    @h.execute('window.dispatchEvent(new Event("resize"));')
    @h.execute('document.dispatchEvent(new KeyboardEvent("keydown", { key: "x" }));')
    @h.pump(rounds: 5)
    assert_equal 1, @h.evaluate("globalThis.__resized || 0")
    assert_equal "x", @h.evaluate("globalThis.__key")
    assert_empty @h.errors, @h.error_report
  end

  # dispatch({ cancelable: true }) returns the event; a listener preventDefault()
  # is observable via the returned event's defaultPrevented.
  def test_dispatch_cancelable
    boot(
      "<!DOCTYPE html><html><head></head><body><div id='root' data-controller='d'></div></body></html>",
      "d" => <<~JS
        class extends Controller {
          fire() { const e = this.dispatch("act", { cancelable: true }); globalThis.__canceled = e.defaultPrevented; }
        }
      JS
    )
    @h.execute(<<~JS)
      document.addEventListener("d:act", (e) => e.preventDefault());
      #{controller_for("root", "d")}.fire();
    JS
    @h.pump(rounds: 5)
    assert_equal true, @h.evaluate("globalThis.__canceled")
    assert_empty @h.errors, @h.error_report
  end

  # A controller method that throws is routed to application.handleError rather
  # than crashing the dispatch.
  def test_controller_error_routed_to_handle_error
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='e'><button id='b' data-action='e#boom'>x</button></div></body></html>",
      "e" => <<~JS
        class extends Controller { boom() { throw new Error("kaboom"); } }
      JS
    )
    @h.execute('globalThis.__errs = []; globalThis.__app.handleError = (err) => globalThis.__errs.push(String(err && err.message));')
    @h.execute('document.getElementById("b").click();')
    @h.pump(rounds: 5)
    assert_equal ["kaboom"], @h.evaluate("globalThis.__errs")
    assert_empty @h.errors, @h.error_report
  end

  # Removing the controller element fires disconnect() and tears down its action
  # listeners (removeEventListener must match the EventListener object by
  # identity, which the memoized wrapper provides).
  def test_disconnect_on_removal
    boot(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div id='root' data-controller='c'><button id='b' data-action='click->c#go'>x</button></div></body></html>",
      "c" => <<~JS
        class extends Controller {
          go() { globalThis.__clicks = (globalThis.__clicks || 0) + 1; }
          disconnect() { globalThis.__disconnected = true; }
        }
      JS
    )
    @h.execute('document.getElementById("b").click();')
    @h.pump(rounds: 5)
    assert_equal 1, @h.evaluate("globalThis.__clicks || 0")

    @h.execute('document.getElementById("root").remove();')
    @h.pump(rounds: 10)
    assert_equal true, @h.evaluate("globalThis.__disconnected")
    assert_empty @h.errors, @h.error_report
  end

  # Application.start() defers until the document is ready: with readyState
  # "loading" it waits for DOMContentLoaded before connecting controllers, then
  # connects once the document becomes interactive. This is the behavior the
  # upstream ApplicationStart suite checks via an iframe + postMessage; the
  # document-lifecycle API (Runtime#set_document_ready_state) exercises it
  # directly, without a second realm.
  def test_application_start_waits_for_dom_ready
    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head></head><body>" \
      "<div data-controller='hello'><span id='out'></span></div></body></html>"
    )
    # Replay the load sequence: the document is still parsing when the app boots.
    @h.runtime.set_document_ready_state("loading")
    assert_equal "loading", @h.evaluate("document.readyState")

    @h.load_script(BUNDLE)
    @h.execute(<<~JS)
      const { Application, Controller } = Stimulus;
      globalThis.__app = Application.start();
      globalThis.__app.register("hello", class extends Controller {
        connect() { document.getElementById("out").textContent = "CONNECTED"; }
      });
    JS
    @h.pump(rounds: 10)
    # Still "loading" → start() is parked on DOMContentLoaded, nothing connected.
    assert_equal "", @h.window.document.get_element_by_id("out").text_content

    # Becoming interactive fires DOMContentLoaded, which releases start().
    @h.runtime.set_document_ready_state("interactive")
    @h.pump(rounds: 10)
    assert_equal "CONNECTED", @h.window.document.get_element_by_id("out").text_content
    assert_empty @h.errors, @h.error_report
  end

  # The real Hotwire stack: Stimulus + Turbo together. A Turbo Drive visit swaps
  # in a body carrying a [data-controller]; Stimulus's MutationObserver picks it
  # up and connect()s the controller on the new page. Skips unless both bundles
  # are vendored.
  def test_stimulus_connects_after_turbo_visit
    turbo = File.expand_path("../../fixtures/turbo.umd.js", __dir__)
    skip "Turbo bundle not vendored (#{turbo})" unless File.exist?(turbo)

    @h = Dommy::Js::BrowserHarness.new(
      "<!DOCTYPE html><html><head><title>A</title></head><body><p id='c'>A</p></body></html>",
      fetch_stub: { "http://localhost/b" => {
        "status" => 200, "contentType" => "text/html",
        "body" => "<html><head><title>B</title></head><body>" \
                  "<div id='w' data-controller='widget'>x</div></body></html>"
      } }
    )
    @h.load_script(turbo)
    @h.load_script(BUNDLE)
    @h.execute(<<~JS)
      const { Application, Controller } = Stimulus;
      globalThis.__app = Application.start();
      globalThis.__app.register("widget", class extends Controller {
        connect() { this.element.textContent = "CONNECTED"; }
      });
    JS
    @h.pump(rounds: 20)

    @h.execute('Turbo.visit("/b");')
    @h.pump(rounds: 40)
    assert_equal "CONNECTED", @h.window.document.get_element_by_id("w").text_content
    assert_empty @h.errors, @h.error_report
  end
end
