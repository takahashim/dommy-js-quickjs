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
    Dommy::Browser.open(html) do |b|
      assert_nil b.evaluate('document.getElementById("late")')
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
