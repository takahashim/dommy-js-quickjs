# frozen_string_literal: true

require "test_helper"

# External-script bytecode caching: a vendored bundle is compiled once per URL
# and the bytecode is reused across fresh VMs (page loads), instead of being
# re-parsed every time.
class Dommy::Js::TestScriptCache < Minitest::Test
  def setup
    Dommy::Js::Quickjs::ScriptCache.clear
  end

  def teardown
    Dommy::Js::Quickjs::ScriptCache.clear
  end

  def resources
    Dommy::Resources.static("https://app.test/bundle.js" => "window.__BUNDLE_RAN = (window.__BUNDLE_RAN || 0) + 1;")
  end

  def page = '<html><head><script src="https://app.test/bundle.js"></script></head><body></body></html>'

  def test_external_script_runs_via_cache_and_is_compiled_once
    # Two independent page loads (fresh VMs) share one compiled entry.
    Dommy::Browser.open(page, url: "https://app.test/", resources: resources) do |b|
      assert_equal 1, b.evaluate("window.__BUNDLE_RAN"), "bundle executed in the first realm"
    end
    assert_equal 1, Dommy::Js::Quickjs::ScriptCache.size, "compiled once, keyed by URL"

    Dommy::Browser.open(page, url: "https://app.test/", resources: resources) do |b|
      assert_equal 1, b.evaluate("window.__BUNDLE_RAN"), "bundle executed in the second realm (fresh VM)"
    end
    assert_equal 1, Dommy::Js::Quickjs::ScriptCache.size, "still one cache entry — bytecode reused, not recompiled"
  end

  def test_compiled_bytecode_runs_identically_to_eval
    res = Dommy::Resources.static("https://app.test/app.js" => "globalThis.X = { go: () => 42 };")
    html = '<html><head><script src="https://app.test/app.js"></script></head><body></body></html>'
    Dommy::Browser.open(html, url: "https://app.test/", resources: res) do |b|
      assert_equal 42, b.evaluate("window.X.go()")
    end
  end
end
