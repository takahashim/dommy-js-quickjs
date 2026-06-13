# frozen_string_literal: true

require "test_helper"

# Phase 4: ES module support — type=module scripts, importmap bare-specifier
# resolution, module sources fetched through Resources, CSS imports stubbed.
class Dommy::Js::TestEsm < Minitest::Test
  ESM = lambda do
    Dommy::Resources.static(
      "https://app.test/stimulus.js" => <<~JS,
        export class Application { static start() { return "STARTED"; } }
      JS
      "https://app.test/application.js" => <<~JS,
        import { Application } from "@hotwired/stimulus";
        import "./theme.css";
        window.Stimulus = Application;
      JS
      "https://app.test/util.js" => 'export const double = (n) => n * 2;',
      "https://app.test/uses-relative.js" => <<~JS
        import { double } from "./util.js";
        window.__double = double(21);
      JS
    )
  end

  IMPORTMAP = '{ "imports": { "@hotwired/stimulus": "https://app.test/stimulus.js" } }'

  def open(body_scripts)
    html = <<~HTML
      <html><head>
        <script type="importmap">#{IMPORTMAP}</script>
        #{body_scripts}
      </head><body></body></html>
    HTML
    Dommy::Browser.open(html, url: "https://app.test/", resources: ESM.call) { |b| yield b }
  end

  def test_inline_module_imports_bare_specifier
    open('<script type="module">import { Application } from "@hotwired/stimulus"; window.__r = Application.start();</script>') do |b|
      assert_equal "STARTED", b.evaluate("window.__r")
    end
  end

  def test_external_module_with_relative_import
    open('<script type="module" src="https://app.test/uses-relative.js"></script>') do |b|
      assert_equal 42, b.evaluate("window.__double"), "relative import resolved against the module URL"
    end
  end

  def test_inline_module_with_relative_import
    open('<script type="module">import { double } from "./util.js"; window.__inlineRel = double(10);</script>') do |b|
      assert_equal 20, b.evaluate("window.__inlineRel"),
                   "inline module's relative import resolves against the document URL"
    end
  end

  def test_inline_module_import_meta_url_is_the_page
    html = <<~HTML
      <html><body><script type="module">
        window.__meta = import.meta.url;
        window.__asset = new URL("./img/a.png", import.meta.url).href;
      </script></body></html>
    HTML
    Dommy::Browser.open(html, url: "https://app.test/dashboard", resources: ESM.call) do |b|
      assert_equal "https://app.test/dashboard", b.evaluate("window.__meta"),
                   "a single inline module's import.meta.url is the clean page URL"
      assert_equal "https://app.test/img/a.png", b.evaluate("window.__asset")
    end
  end

  def test_multiple_inline_modules_share_the_clean_import_meta_url
    html = <<~HTML
      <html><body>
        <script type="module">window.__m1 = import.meta.url;</script>
        <script type="module">window.__m2 = import.meta.url;</script>
      </body></html>
    HTML
    Dommy::Browser.open(html, url: "https://app.test/page", resources: ESM.call) do |b|
      assert_equal "https://app.test/page", b.evaluate("window.__m1")
      assert_equal "https://app.test/page", b.evaluate("window.__m2"),
                   "a second inline module also reports the clean page URL (not a #fragment)"
    end
  end

  def test_css_import_is_an_empty_module
    open('<script type="module" src="https://app.test/application.js"></script>') do |b|
      assert_equal "function", b.evaluate("typeof window.Stimulus"), "module ran past the CSS import without crashing"
      assert_equal "STARTED", b.evaluate("window.Stimulus.start()")
    end
  end

  def test_classic_and_module_scripts_coexist
    scripts = <<~HTML
      <script>window.__order = ["classic"];</script>
      <script type="module">window.__order.push("module");</script>
    HTML
    open(scripts) do |b|
      assert_equal %w[classic module], b.evaluate("window.__order")
    end
  end

  def test_dynamic_import
    open('<script type="module">import("@hotwired/stimulus").then((m) => { window.__dyn = m.Application.start(); });</script>') do |b|
      b.settle
      assert_equal "STARTED", b.evaluate("window.__dyn"), "dynamic import() resolves through the loader"
    end
  end

  def test_unresolvable_module_is_isolated
    # A bad import is a module error: it is collected (and would fail a strict
    # browser) but must not abort the rest of boot — the later classic script
    # still runs.
    html = <<~HTML
      <html><head>
        <script type="module">import "nonexistent-package"; window.__bad = true;</script>
        <script>window.__after = "ran";</script>
      </head><body></body></html>
    HTML
    Dommy::Browser.open(html, url: "https://app.test/", resources: ESM.call, strict: false) do |b|
      assert_equal "ran", b.evaluate("window.__after")
      assert(b.js_errors.any? { |e| e.message.include?("nonexistent-package") }, "the module error was collected")
    end
  end

  # --- ImportMap unit ---

  def test_import_map_exact_and_trailing_slash
    map = Dommy::Js::Quickjs::ImportMap.parse(<<~JSON)
      { "imports": { "app": "/app.js", "lib/": "/vendor/lib/" } }
    JSON
    assert_equal "/app.js", map.resolve("app")
    assert_equal "/vendor/lib/x/y.js", map.resolve("lib/x/y.js")
    assert_nil map.resolve("unmapped")
  end

  def test_import_map_scope_overrides_top_level
    map = Dommy::Js::Quickjs::ImportMap.parse(<<~JSON)
      { "imports": { "lodash": "/global/lodash.js" },
        "scopes": { "https://app.test/admin/": { "lodash": "/admin/lodash.js" } } }
    JSON
    assert_equal "/global/lodash.js", map.resolve("lodash", "https://app.test/main.js")
    assert_equal "/admin/lodash.js", map.resolve("lodash", "https://app.test/admin/page.js")
  end

  def test_empty_import_map
    assert Dommy::Js::Quickjs::ImportMap.parse("").empty?
    assert Dommy::Js::Quickjs::ImportMap.parse("not json").empty?
  end
end
