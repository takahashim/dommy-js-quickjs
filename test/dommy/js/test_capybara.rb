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
  APP = lambda do |_env|
    body = <<~HTML
      <html><body>
        <h1 class="title">Hello</h1>
        <button class="primary">Click me</button>
      </body></html>
    HTML
    [200, {"content-type" => "text/html"}, [body]]
  end

  def setup
    @driver = Capybara::Dommy::Driver.new(APP, default_host: "http://example.org")
    @driver.visit("/")
  end

  def test_evaluate_primitive
    assert_equal 3, @driver.evaluate_script("1 + 2")
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
