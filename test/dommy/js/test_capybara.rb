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

  # install_capybara! is idempotent: requiring/enabling repeatedly prepends once.
  def test_install_capybara_is_idempotent
    Dommy::Js::Quickjs.install_capybara!
    Dommy::Js::Quickjs.install_capybara!
    count = Capybara::Dommy::Driver.ancestors.count { |mod| mod.equal?(Dommy::Js::Quickjs::CapybaraDriver) }
    assert_equal 1, count
  end
end
