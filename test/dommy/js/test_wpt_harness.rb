# frozen_string_literal: true

require "test_helper"

# The WPT-JS harness: testharness.js runs against the bridge and per-subtest
# results are harvested. This is the conformance lens for the JS-facing DOM —
# it lets real WPT `.any.js` / `.window.js` files be run via #run_file.
class Dommy::Js::TestWptHarness < Minitest::Test
  def setup
    skip "testharness.js not vendored" unless Dommy::Js::WptHarness.available?

    @wpt = Dommy::Js::WptHarness.new
  end

  def teardown
    @wpt&.dispose
  end

  # The harness reports pass/fail per subtest, with the assertion message on fail.
  def test_reports_pass_and_fail
    results = @wpt.run(<<~JS)
      test(() => assert_equals(1 + 1, 2), "addition");
      test(() => assert_equals(1 + 1, 3), "wrong addition");
      test(() => assert_true(false), "false is not true");
    JS

    by_name = results.to_h { |r| [r.name, r] }
    assert by_name["addition"].pass?
    refute by_name["wrong addition"].pass?
    assert_equal "FAIL", by_name["wrong addition"].status_name
    assert_includes by_name["wrong addition"].message, "expected 3 but got 2"
    refute by_name["false is not true"].pass?
  end

  # testharness assertions run against the real bridge DOM — the actual point:
  # the JS-facing DOM (instanceof, createElement, classList, …) is spec-shaped
  # enough to satisfy WPT-style assertions.
  def test_dom_assertions_against_bridge
    results = @wpt.run(<<~JS)
      test(() => {
        const el = document.createElement("div");
        assert_true(el instanceof HTMLElement, "createElement -> HTMLElement");
        assert_equals(el.tagName, "DIV");
      }, "createElement / instanceof");

      test(() => {
        const el = document.createElement("span");
        el.classList.add("a");
        el.classList.add("b");
        assert_true(el.classList.contains("a"));
        assert_equals(el.getAttribute("class"), "a b");
      }, "classList");

      test(() => {
        const parent = document.createElement("ul");
        const child = document.createElement("li");
        parent.appendChild(child);
        assert_equals(parent.children.length, 1);
        assert_equals(child.parentNode, parent);
        parent.removeChild(child);
        assert_equals(parent.children.length, 0);
      }, "appendChild / removeChild");
    JS

    failures = results.reject(&:pass?)
    assert_empty failures, failures.map(&:to_s).join("\n")
    assert_equal 3, results.size
  end

  # Async tests settle once the scheduler is pumped.
  def test_async_test
    results = @wpt.run(<<~JS)
      async_test((t) => {
        Promise.resolve().then(t.step_func_done(() => {
          assert_equals(2 + 2, 4);
        }));
      }, "promise microtask resolves");
    JS
    assert results.first.pass?, results.first.to_s
  end
end
