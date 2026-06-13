# frozen_string_literal: true

require "test_helper"

# capybara-dommy isn't published yet, so it's only on the load path inside the
# dommy monorepo. In a standalone clone, skip this file rather than aborting the
# whole suite at load time.
begin
  require "dommy/js/quickjs/capybara"
rescue LoadError
  warn "skipping test_capybara.rb: capybara-dommy not available"
  return
end

# Drives the real Capybara::Dommy::Driver with the JS adapter prepended, so
# execute_script / evaluate_script run against the current Dommy document.
class Dommy::Js::TestCapybaraAdapter < Minitest::Test
  APP = lambda do |env|
    case env["PATH_INFO"]
    when "/api/message"
      [200, {"content-type" => "text/plain"}, ["from rack"]]
    when "/frame"
      [200, {"content-type" => "text/html"},
       ["<html><body><h1 class='frame-title'>InFrame</h1></body></html>"]]
    when "/host-scripted-frame"
      [200, {"content-type" => "text/html"},
       ["<html><body><iframe src='/scripts-frame'></iframe></body></html>"]]
    when "/scripts-frame"
      [200, {"content-type" => "text/html"}, [<<~HTML]]
        <html><body><h1 class="frame-title">InFrame</h1><script>
          window.__frame = ["inline"];
          document.addEventListener("DOMContentLoaded", () => window.__frame.push("DCL"));
        </script></body></html>
      HTML
    when "/ext.js"
      [200, {"content-type" => "application/javascript"}, ['window.__order.push("external");']]
    when "/missing.js"
      [404, {"content-type" => "text/plain"}, ["not found"]]
    when "/scripts"
      [200, {"content-type" => "text/html"}, [<<~HTML]]
        <html><body>
          <h1 id="head">before</h1>
          <script>
            window.__order = ["inline"];
            document.getElementById("head").textContent = "after";
          </script>
          <script src="/ext.js"></script>
          <script>
            document.addEventListener("DOMContentLoaded", () => window.__order.push("DCL"));
            window.addEventListener("load", () => window.__order.push("load"));
          </script>
          <script type="module">window.__order.push("MODULE_RAN");</script>
        </body></html>
      HTML
    when "/scripts-404"
      [200, {"content-type" => "text/html"}, [<<~HTML]]
        <html><body>
          <script src="/missing.js"></script>
          <script>window.__ran = "inline-after-404";</script>
        </body></html>
      HTML
    else
      body = <<~HTML
        <html><body>
          <h1 class="title">Hello</h1>
          <button class="primary">Click me</button>
          <iframe src="/frame"></iframe>
        </body></html>
      HTML
      [200, {"content-type" => "text/html"}, [body]]
    end
  end

  def setup
    @driver = Capybara::Dommy::Driver.new(APP, default_host: "http://example.org")
    @driver.visit("/")
  end

  def test_evaluate_primitive
    assert_equal 3, @driver.evaluate_script("1 + 2")
  end

  def test_page_load_installs_time_pump
    assert @driver.wait?
  end

  def test_evaluate_dom_property
    assert_equal "Hello", @driver.evaluate_script('document.querySelector("h1").textContent')
  end

  def test_execute_script_mutates_dom
    @driver.execute_script('document.querySelector("h1").textContent = "Changed"')
    assert_equal "Changed", @driver.evaluate_script('document.querySelector("h1").textContent')
    assert_includes @driver.html, "Changed"
  end

  def test_evaluate_returns_capybara_node
    node = @driver.evaluate_script('document.querySelector("h1")')
    assert_kind_of Capybara::Dommy::Node, node
    assert_equal "h1", node.tag_name
    assert_equal "Hello", node.all_text
    assert_equal "title", node[:class]
  end

  def test_evaluate_via_window
    assert_equal "Hello", @driver.evaluate_script('window.document.querySelector("h1").textContent')
  end

  def test_evaluate_resolves_promise
    assert_equal 7, @driver.evaluate_script("Promise.resolve(3 + 4)")
  end

  # execute_script drains microtasks, so queued .then side effects land.
  def test_execute_script_drains_microtasks
    @driver.execute_script('Promise.resolve().then(() => { document.querySelector("h1").textContent = "Async"; });')
    assert_equal "Async", @driver.evaluate_script('document.querySelector("h1").textContent')
  end

  def test_find_pumps_deterministic_time
    @driver.execute_script(<<~JS)
      setTimeout(() => {
        const p = document.createElement("p");
        p.className = "late";
        p.textContent = "Later";
        document.body.appendChild(p);
      }, 50);
    JS

    nodes = @driver.find_css(".late")

    assert_equal 1, nodes.length
    assert_equal "Later", nodes.first.all_text
  end

  def test_fetch_uses_rack_session_network_bridge
    assert_equal "from rack", @driver.evaluate_script('fetch("/api/message").then((r) => r.text())')
  end

  def test_reset_resubscribes_new_rack_session
    @driver.reset!
    @driver.visit("/")

    assert_equal "from rack", @driver.evaluate_script('fetch("/api/message").then((r) => r.text())')
  end

  # Each window is its own realm: execute/evaluate inside a switched-to frame
  # run against the FRAME's document and globals, and returning to the top
  # leaves the top realm's state intact (not destroyed by the frame visit).
  def test_script_targets_current_frame_realm
    assert_equal "title", @driver.evaluate_script('document.querySelector("h1").className')
    @driver.execute_script('globalThis.__realm = "top";')

    @driver.switch_to_frame(@driver.find_css("iframe").first)

    assert_equal "frame-title", @driver.evaluate_script('document.querySelector("h1").className')
    assert_nil @driver.evaluate_script("globalThis.__realm"), "frame realm must not see the top global"
    @driver.execute_script('globalThis.__realm = "frame";')
    assert_equal "frame", @driver.evaluate_script("globalThis.__realm")

    @driver.switch_to_frame(:top)
    assert_equal "title", @driver.evaluate_script('document.querySelector("h1").className')
    assert_equal "top", @driver.evaluate_script("globalThis.__realm"), "top realm state must survive the frame visit"
  end

  # querySelectorAll returns an array whose every element is wrapped as a node.
  def test_evaluate_returns_array_of_nodes
    nodes = @driver.evaluate_script('document.querySelectorAll("h1, button")')
    assert_equal 2, nodes.length
    assert(nodes.all? { |n| n.is_a?(Capybara::Dommy::Node) })
    assert_equal %w[h1 button], nodes.map(&:tag_name)
  end

  # A non-element bridge object (the Document) has no Capybara node type -> nil.
  def test_evaluate_non_element_node_is_nil
    assert_nil @driver.evaluate_script("document")
  end

  # A page's <script> tags run on load: inline and external interleaved in
  # document order, then DOMContentLoaded, then load. Module scripts are skipped.
  def test_page_load_runs_scripts_in_document_order
    @driver.visit("/scripts")

    assert_equal %w[inline external MODULE_RAN DCL load], @driver.evaluate_script("window.__order")
    assert_equal "after", @driver.evaluate_script('document.getElementById("head").textContent'),
                 "inline script's DOM mutation must be visible"
    assert_includes @driver.evaluate_script("window.__order"), "MODULE_RAN", "type=module now runs (Phase 4)"
    assert_equal "complete", @driver.evaluate_script("document.readyState")
  end

  # A frame's own <script> runs (and its DOMContentLoaded fires) when the frame
  # realm is built on switch_to_frame — proving per-realm script coverage.
  def test_frame_scripts_run_on_switch
    @driver.visit("/host-scripted-frame")
    @driver.switch_to_frame(@driver.find_css("iframe").first)

    assert_equal %w[inline DCL], @driver.evaluate_script("window.__frame"),
                 "frame page's inline script and its DOMContentLoaded must run"
  end

  # A failed external fetch (404) does not abort the sweep: later inline scripts
  # still run.
  def test_failed_external_script_does_not_abort_load
    @driver.visit("/scripts-404")
    assert_equal "inline-after-404", @driver.evaluate_script("window.__ran")
  end

  # install_capybara! is idempotent: requiring/enabling repeatedly prepends once.
  def test_install_capybara_is_idempotent
    Dommy::Js::Quickjs.install_capybara!
    Dommy::Js::Quickjs.install_capybara!
    count = Capybara::Dommy::Driver.ancestors.count { |mod| mod.equal?(Dommy::Js::Quickjs::CapybaraDriver) }
    assert_equal 1, count
  end
end
