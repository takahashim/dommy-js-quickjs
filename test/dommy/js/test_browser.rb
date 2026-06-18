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
      assert_equal true, b.evaluate('new Option("Hi", "v", true).selected')
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
end
