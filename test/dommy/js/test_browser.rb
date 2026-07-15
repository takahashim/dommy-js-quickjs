# frozen_string_literal: true

require "test_helper"

# Dommy::Browser — the standalone lightweight test browser: parse HTML, boot its
# <script> tags, fire DOMContentLoaded/load, and collect JS errors.
class Dommy::Js::TestBrowser < Minitest::Test
  PAGE = <<~HTML
    <html><body>
      <h1 id="head">before</h1>
      <script>
        window.__order = ["inline"];
        document.__current = document.currentScript ? document.currentScript.id : null;
        document.getElementById("head").textContent = "after";
      </script>
      <script id="ext" src="/ext.js"></script>
      <script>
        document.addEventListener("DOMContentLoaded", () => window.__order.push("DCL"));
        window.addEventListener("load", () => window.__order.push("load"));
      </script>
      <script type="module">window.__order.push("MODULE_RAN");</script>
    </body></html>
  HTML

  def resources
    Dommy::Resources.static(
      "/ext.js" => {"content_type" => "application/javascript",
                    "body" => 'window.__order.push("external"); window.__extScript = document.currentScript && document.currentScript.id;'}
    )
  end

  def test_boots_scripts_in_document_order_with_lifecycle
    Dommy::Browser.open(PAGE, url: "http://example.test/", resources: resources) do |b|
      assert_equal %w[inline external MODULE_RAN DCL load], b.evaluate("window.__order")
      assert_equal "after", b.evaluate('document.getElementById("head").textContent')
      assert_equal "complete", b.evaluate("document.readyState")
      assert_includes b.evaluate("window.__order"), "MODULE_RAN", "type=module now runs (Phase 4)"
    end
  end

  # Legacy named constructors: `new Image()` / `new Audio()` / `new Option()`
  # build the matching element and share the target interface's prototype, so
  # `instanceof` and `.constructor` resolve like a browser. premium.lp-note.com
  # (Nuxt) uses `new Image()` for tracking pixels — without this it threw
  # "'Image' is not defined".
  def test_legacy_named_constructors
    Dommy::Browser.open("<html><body></body></html>", url: "http://example.test/") do |b|
      # Image
      assert_equal "function", b.evaluate("typeof Image")
      assert_equal "IMG", b.evaluate("new Image().tagName")
      assert_equal true, b.evaluate("new Image() instanceof HTMLImageElement")
      assert_equal "HTMLImageElement", b.evaluate("new Image().constructor.name")
      assert_equal "32", b.evaluate('new Image(32, 48).getAttribute("width")')
      assert_equal "48", b.evaluate('new Image(32, 48).getAttribute("height")')
      assert_equal true, b.evaluate("window.Image === Image")
      # Audio
      assert_equal "AUDIO", b.evaluate("new Audio().tagName")
      assert_equal "auto", b.evaluate('new Audio().getAttribute("preload")')
      assert_equal "/s.mp3", b.evaluate('new Audio("/s.mp3").getAttribute("src")')
      assert_equal true, b.evaluate("new Audio() instanceof HTMLAudioElement")
      # Option
      assert_equal "OPTION", b.evaluate("new Option().tagName")
      assert_equal "Hi", b.evaluate('new Option("Hi", "v").textContent')
      assert_equal "v", b.evaluate('new Option("Hi", "v").value')
      # 3rd arg is defaultSelected (the `selected` content attribute); the
      # selectedness is set by the 4th arg (WHATWG Option constructor).
      assert_equal true, b.evaluate('new Option("Hi", "v", true).defaultSelected')
      assert_equal false, b.evaluate('new Option("Hi", "v", true).selected')
      assert_equal true, b.evaluate('new Option("Hi", "v", true, true).selected')
      assert_equal true, b.evaluate("new Option() instanceof HTMLOptionElement")
    end
  end

  # `window.Promise` must be the engine's native Promise (=== globalThis.Promise),
  # like a real browser — not the host's Ruby-backed PromiseConstructor. If the
  # host one leaked onto the window, feature detection (core-js et al.) would see
  # a non-conforming Promise and install a polyfill whose microtasks the host
  # can't flush, silently stalling `await` and hanging SPA hydration.
  def test_window_promise_is_the_native_promise
    Dommy::Browser.open("<html><body></body></html>", url: "http://x.test/") do |b|
      assert_equal true, b.evaluate("window.Promise === globalThis.Promise")
      assert_equal true, b.evaluate("/native code/.test(String(window.Promise))"), "not the host proxy"
      assert_equal true, b.evaluate("window.Promise[Symbol.species] === window.Promise")
      assert_equal "function", b.evaluate("typeof window.Promise.prototype.then")
      assert_equal 42, b.evaluate("(async () => await window.Promise.resolve(42))()"), "resolves as a real microtask"
    end
  end

  # `window.X` for JS builtins must BE the engine's native global (like a real
  # browser: `window.console === console`). The host's __js_get__ returned
  # sentinels for console/Object/Array/JSON that crossed as STRINGS, so e.g.
  # `x in window.console` threw "invalid 'in' operand" (note.com's console
  # wrapper hit this).
  def test_window_js_builtins_are_the_native_globals
    Dommy::Browser.open("<html><body></body></html>", url: "http://x.test/") do |b|
      %w[console Object Array JSON Math Date RegExp Map Set].each do |g|
        assert_equal true, b.evaluate("window.#{g} === globalThis.#{g}"), "window.#{g} is the native #{g}"
      end
      assert_equal "object", b.evaluate("typeof window.console")
      assert_equal true, b.evaluate('"log" in window.console'), "in-operator works on window.console"
      assert_equal "function", b.evaluate("typeof window.console.log")
    end
  end

  # `PromiseRejectionEvent` must exist as a global constructor: Promise
  # feature-detection (core-js et al.) checks for it, and without it swaps in a
  # polyfill whose microtask queue the host can't flush — which silently starves
  # every `.then`/await and hangs SPA hydration (note.com rendered only a shell).
  def test_promise_rejection_event_exists
    Dommy::Browser.open("<html><body></body></html>", url: "http://x.test/") do |b|
      assert_equal "function", b.evaluate("typeof PromiseRejectionEvent")
      assert_equal "function", b.evaluate("typeof window.PromiseRejectionEvent")
      assert_equal true, b.evaluate("new PromiseRejectionEvent('unhandledrejection', { reason: 'boom' }) instanceof Event")
      assert_equal "boom", b.evaluate("new PromiseRejectionEvent('unhandledrejection', { reason: 'boom' }).reason")
      assert_equal "unhandledrejection", b.evaluate("new PromiseRejectionEvent('unhandledrejection', {}).type")
      # the payoff: the engine's native Promise stays the global Promise (no polyfill bait)
      assert_equal true, b.evaluate("(async () => {})().constructor === globalThis.Promise")
    end
  end

  # A blank <iframe> (no src or src="about:blank") inserted into the DOM gets a
  # real, complete nested document and fires `load` asynchronously (handler
  # commonly attached after appendChild), like a real browser. FingerprintJS's
  # withIframe (its font sources) appends to `iframe.contentWindow.document.body`
  # and polls its readyState — a never-firing load + null contentWindow hung
  # note.com's tracking plugin and its whole Nuxt hydration.
  def test_blank_iframe_fires_load_and_has_a_usable_content_document
    html = <<~HTML
      <html><body><script>
        window.__loaded = false;
        var f = document.createElement("iframe");
        f.src = "about:blank";
        document.body.appendChild(f);          // inserted first
        f.onload = function () { window.__loaded = true; }; // handler after
      </script></body></html>
    HTML
    Dommy::Browser.open(html, url: "http://x.test/") do |b|
      f = 'document.querySelector("iframe")'
      assert_equal true, b.evaluate("window.__loaded"), "blank iframe fired load"
      assert_equal true, b.evaluate("!!#{f}.contentWindow"), "contentWindow is a real window (not null)"
      assert_equal "complete", b.evaluate("#{f}.contentWindow.document.readyState")
      # FingerprintJS-style: append + measure inside the iframe document
      assert_equal 1, b.evaluate(<<~JS)
        (function () {
          var d = #{f}.contentWindow.document;
          d.body.appendChild(d.createElement("span"));
          return d.body.childNodes.length;
        })()
      JS
    end
  end

  # A blank iframe's contentWindow is its own realm: `contentWindow.Event` /
  # `.DOMException` / `.Range` resolve to real (constructable) constructors, not
  # bare host proxies — so cross-frame `new cw.Event(...)` and DOM machinery
  # (Range) work inside the nested document. This is the per-frame constructor
  # seeding that WPT's iframe-based tests (Range-insertNode etc.) rely on.
  def test_blank_iframe_content_window_has_its_own_constructors
    html = <<~HTML
      <html><body><iframe id="f"></iframe></body></html>
    HTML
    Dommy::Browser.open(html, url: "http://x.test/") do |b|
      cw = 'document.getElementById("f").contentWindow'
      assert_equal "function", b.evaluate("typeof #{cw}.Event")
      assert_equal "function", b.evaluate("typeof #{cw}.DOMException")
      assert_equal "function", b.evaluate("typeof #{cw}.Range")
      assert_equal "function", b.evaluate("typeof #{cw}.Node")
      # The seeded constructors are constructable across the frame boundary.
      # (Parenthesize the callee — `new a.b("x").c` would bind "x" as `new`'s args.)
      assert_equal "hi", b.evaluate("new (#{cw}.Event)('hi').type")
      assert_equal "AbortError", b.evaluate("new (#{cw}.DOMException)('m', 'AbortError').name")
      # Range machinery works inside the nested document.
      assert_equal "<p>ab<span>X</span>cdef</p>", b.evaluate(<<~JS)
        (function () {
          var cd = document.getElementById("f").contentDocument;
          cd.body.innerHTML = "<p>abcdef</p>";
          var text = cd.body.firstChild.firstChild;
          var r = cd.createRange();
          r.setStart(text, 2); r.setEnd(text, 2);
          var span = cd.createElement("span");
          span.textContent = "X";
          r.insertNode(span);
          return cd.body.firstChild.outerHTML;
        })()
      JS
    end
  end

  def test_current_script_is_set_during_execution
    Dommy::Browser.open(PAGE, url: "http://example.test/", resources: resources) do |b|
      # The inline script saw a non-null currentScript (its own element; no id → "").
      assert_equal "string", b.evaluate("typeof document.__current")
      # The external script saw its own element id while executing.
      assert_equal "ext", b.evaluate("window.__extScript")
      # Outside any script run, currentScript is null again.
      assert_nil b.evaluate("document.currentScript")
    end
  end

  def test_external_script_resolves_through_resources
    res = Dommy::Resources.static("/app.js" => 'globalThis.App = { ok: true };')
    html = '<html><head><script src="/app.js"></script></head><body></body></html>'
    Dommy::Browser.open(html, url: "http://example.test/", resources: res) do |b|
      assert_equal true, b.evaluate("window.App.ok")
    end
  end

  def test_strict_mode_raises_on_uncaught_script_error
    html = '<html><body><script>throw new Error("boom");</script></body></html>'
    err = assert_raises(Dommy::Browser::JsError) do
      Dommy::Browser.open(html)
    end
    assert_includes err.message, "boom"
  end

  def test_allow_js_errors_suppresses_strict_failure
    html = "<html><body></body></html>"
    Dommy::Browser.open(html, strict: true) do |b|
      b.allow_js_errors do
        b.execute('Promise.reject(new TypeError("expected"));')
        b.settle
      end
      assert(b.js_errors.any? { |e| e.message.include?("expected") })
    end
  end

  def test_non_strict_collects_without_raising
    html = '<html><body><script>throw new Error("ignored");</script></body></html>'
    b = Dommy::Browser.new(html, strict: false)
    assert(b.js_errors.any? { |e| e.message.include?("ignored") })
  ensure
    b&.dispose
  end

  def test_console_is_collected
    Dommy::Browser.open("<html><body></body></html>") do |b|
      b.execute('console.warn("hi", 42);')
      log = b.console.find { |l| l.to_s.include?("hi") }
      refute_nil log
      assert_equal :warning, log.severity
    end
  end

  def test_settle_runs_due_now_timer_work
    html = <<~HTML
      <html><body><script>
        setTimeout(() => { const p = document.createElement("p"); p.id = "late"; document.body.appendChild(p); }, 0);
      </script></body></html>
    HTML
    Dommy::Browser.open(html, settle: false) do |b|
      assert_nil b.evaluate('document.getElementById("late")'), "settle: false leaves the timer pending"
      b.settle
      refute_nil b.evaluate('document.getElementById("late")')
    end
  end

  def test_execute_scripts_false_skips_boot
    html = '<html><body><script>document.body.setAttribute("data-ran", "1");</script></body></html>'
    Dommy::Browser.open(html, execute_scripts: false) do |b|
      assert_nil b.evaluate('document.body.getAttribute("data-ran")')
    end
  end

  # --- N3: cross-document navigation with a real JS realm swap ---

  def nav_resources
    Dommy::Resources.static(
      "/" => {"content_type" => "text/html",
              "body" => '<!doctype html><html><body><h1>A</h1>' \
                        '<script>window.__page = "A"; document.title = "PageA";</script></body></html>'},
      "/b" => {"content_type" => "text/html",
               "body" => '<!doctype html><html><body><h1>B</h1>' \
                         '<script>window.__leaked = (typeof window.__page !== "undefined"); ' \
                         'document.title = "PageB";</script></body></html>'}
    )
  end

  def test_js_navigation_replaces_document_in_a_fresh_realm
    b = Dommy::Browser.visit("http://localhost/", resources: nav_resources)
    assert_equal "PageA", b.evaluate("document.title")

    # location.href= is a task: the swap is deferred, not synchronous.
    b.execute("location.href = '/b'")
    assert_equal "PageA", b.evaluate("document.title"), "not swapped mid-script"

    b.settle
    assert_equal "PageB", b.evaluate("document.title")
    assert_equal "http://localhost/b", b.current_url
    assert_equal false, b.evaluate("window.__leaked"), "the new page runs in a fresh realm"
    assert_equal "undefined", b.evaluate("typeof window.__page")
    assert_equal 2, b.history.length
  ensure
    b&.dispose
  end

  def test_back_forward_refetch_reboots_each_realm
    b = Dommy::Browser.visit("http://localhost/", resources: nav_resources)
    b.execute("location.href = '/b'")
    b.settle
    assert_equal "PageB", b.evaluate("document.title")

    b.back
    assert_equal "PageA", b.evaluate("document.title"), "back re-fetches and reboots page A"
    assert_equal "A", b.evaluate("window.__page")

    b.forward
    assert_equal "PageB", b.evaluate("document.title")
  ensure
    b&.dispose
  end

  # --- inline event-handler content attributes (onclick="…", …) ---

  def test_inline_event_handler_attributes_fire
    html = <<~HTML
      <html><body>
        <button id="c" onclick="window.__n = (window.__n || 0) + 1">c</button>
        <button id="t" onclick="this.setAttribute('data-hit', '1')">t</button>
        <form id="f" onsubmit="window.__sub = 1; event.preventDefault()">
          <button type="submit">s</button>
        </form>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.execute("document.getElementById('c').click()")
      b.execute("document.getElementById('c').click()")
      assert_equal 2, b.evaluate("window.__n"), "onclick fires on each click"

      b.execute("document.getElementById('t').click()")
      assert_equal "1", b.evaluate("document.getElementById('t').getAttribute('data-hit')"),
        "`this` inside the handler is the element"

      b.execute("document.getElementById('f').requestSubmit()")
      assert_equal 1, b.evaluate("window.__sub"), "`event` is in scope and preventDefault works"

      assert_equal "function", b.evaluate("typeof document.getElementById('c').onclick"),
        "the compiled handler is readable as the onclick IDL property"
    end
  end

  def test_inline_event_handler_fires_on_cloned_element
    # cloneNode copies on* content attributes at the backend, bypassing the
    # setAttribute trap that compiles inline handlers — so the clone must be
    # (re)wired, or its handler silently never fires. Covers the template →
    # cloneNode pattern (WPT dom/events/Event-dispatch-single-activation).
    html = <<~HTML
      <html><body>
        <template><button onclick="window.__hits = (window.__hits || 0) + 1">x</button></template>
        <div id="host"></div>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.execute(<<~JS)
        const tpl = document.querySelector("template");
        const clone = tpl.content.firstElementChild.cloneNode(true);
        document.getElementById("host").appendChild(clone);
        clone.click();
      JS
      assert_equal 1, b.evaluate("window.__hits"), "a cloned element's inline handler fires"
      assert_equal "function", b.evaluate("typeof document.querySelector('#host button').onclick"),
        "the clone's compiled handler is readable as the IDL property"
    end
  end

  def test_inline_handler_lexical_scope
    # An inline handler resolves bare names against [element, form owner,
    # document] before the global (the HTML "compile" scope chain).
    html = <<~HTML
      <html><body>
        <table><tr><td id="c" onclick="window.__el = typeof cellIndex; window.__doc = typeof getElementById">x</td></tr></table>
        <form id="f"><input id="i" onclick="window.__form = typeof elements"></form>
      </body></html>
    HTML
    Dommy::Browser.open(html) do |b|
      b.execute("document.getElementById('c').click()")
      assert_equal "number", b.evaluate("window.__el"), "element member (cellIndex) is in scope"
      assert_equal "function", b.evaluate("window.__doc"), "document member (getElementById) is in scope"

      b.execute("document.getElementById('i').click()")
      assert_equal "object", b.evaluate("window.__form"), "form-owner member (elements) is in scope"
    end
  end

  def test_inline_handler_return_false_cancels
    html = '<html><body><form id="f" onsubmit="return false"><button type="submit">go</button></form></body></html>'
    Dommy::Browser.open(html) do |b|
      prevented = b.evaluate(<<~JS)
        (() => {
          const e = new SubmitEvent("submit", { cancelable: true, bubbles: true });
          document.getElementById("f").dispatchEvent(e);
          return e.defaultPrevented;
        })()
      JS
      assert_equal true, prevented, 'onsubmit="return false" cancels the event'
    end
  end

  def test_body_onload_inline_handler_reflects_to_the_window
    html = '<html><body onload="window.__loaded = 1" onclick="window.__bodyclick = 1">x</body></html>'
    Dommy::Browser.open(html) do |b|
      # onload on <body> is a window-reflected handler: it fires on window load.
      assert_equal 1, b.evaluate("window.__loaded"), "<body onload> fires"
      # A non-reflected handler (onclick) stays on the body element.
      b.execute("document.body.click()")
      assert_equal 1, b.evaluate("window.__bodyclick"), "<body onclick> stays on the body"
    end
  end

  # --- window event handler IDL attributes (window.onload = fn, …) ---

  def test_window_event_handler_idl_attributes
    Dommy::Browser.open("<html><body><script>window.onload = () => { window.__wl = 1 }</script></body></html>") do |b|
      assert_equal 1, b.evaluate("window.__wl"), "window.onload = fn fires on load"
      assert_equal "function", b.evaluate("typeof window.onload"), "it reads back as the handler"
    end

    Dommy::Browser.open("<html><body></body></html>") do |b|
      # A registered handler fires; setting it to null removes it; reassigning
      # replaces rather than accumulates.
      b.execute("window.__n = 0; window.onresize = () => { window.__n++ }; dispatchEvent(new Event('resize'))")
      assert_equal 1, b.evaluate("window.__n")
      b.execute("window.onresize = null; dispatchEvent(new Event('resize'))")
      assert_equal 1, b.evaluate("window.__n"), "null removes the handler"
      assert_nil b.evaluate("window.onresize"), "an unset handler reads back as null"

      # A non-handler on-prefixed global stays a plain expando (not an event
      # handler), so it round-trips unchanged.
      b.execute("window.onboarding = { step: 3 }")
      assert_equal 3, b.evaluate("window.onboarding.step")
    end
  end
end
