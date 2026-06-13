# frozen_string_literal: true

require "test_helper"

# CSS conformance run END-TO-END through QuickJS: testharness.js assertions
# call the JS-facing CSSOM (getComputedStyle / CSS.supports / matchMedia /
# element.style / document.styleSheets), so this exercises the whole JS ->
# host bridge -> Ruby cascade path — the binding layer that the pure-Ruby
# dommy conformance suite can't reach.
#
# Test scripts are written in the documented testharness.js style (test() +
# assert_*); they are not copied from WPT files.
#
# Mirrors: css/cssom/getComputedStyle-*, css/css-conditional/,
#          css/mediaqueries/, css/cssom/CSSStyleSheet*
class Dommy::Js::TestWptCss < Minitest::Test
  def setup
    skip "testharness.js not vendored" unless Dommy::Js::WptHarness.available?
  end

  def run_css(html, script)
    wpt = Dommy::Js::WptHarness.new(html)
    results = wpt.run(script)
    failures = results.reject(&:pass?)
    assert_empty failures, failures.map(&:to_s).join("\n")
    refute_empty results
  ensure
    wpt&.dispose
  end

  def test_get_computed_style_resolved_values
    run_css(<<~HTML, <<~JS)
      <!DOCTYPE html>
      <style>
        #t { color: red; background: #00ff00; font-size: 20px; letter-spacing: 2em;
             opacity: 2; border: 2px solid currentColor }
      </style>
      <p id="t">x</p>
    HTML
      const cs = getComputedStyle(document.getElementById("t"));
      test(() => assert_equals(cs.color, "rgb(255, 0, 0)"), "named color -> rgb");
      test(() => assert_equals(cs.backgroundColor, "rgb(0, 255, 0)"), "hex -> rgb");
      test(() => assert_equals(cs.letterSpacing, "40px"), "em resolves against font-size");
      test(() => assert_equals(cs.opacity, "1"), "opacity clamps to 1");
      test(() => assert_equals(cs.borderTopWidth, "2px"), "border shorthand longhand");
      test(() => assert_equals(cs.borderTopColor, "rgb(255, 0, 0)"), "currentColor in border");
    JS
  end

  def test_css_supports
    run_css("<!DOCTYPE html><p>x</p>", <<~JS)
      test(() => assert_true(CSS.supports("(display: grid)")), "condition form");
      test(() => assert_true(CSS.supports("display", "grid")), "two-argument form");
      test(() => assert_false(CSS.supports("not (display: grid)")), "not()");
      test(() => assert_true(CSS.supports("(display: grid) and (color: red)")), "and");
      test(() => assert_true(CSS.supports("selector(a:hover)")), "selector()");
    JS
  end

  def test_match_media
    run_css("<!DOCTYPE html><p>x</p>", <<~JS)
      test(() => assert_true(matchMedia("(min-width: 100px)").matches), "min-width true");
      test(() => assert_false(matchMedia("(min-width: 5000px)").matches), "min-width false");
      test(() => assert_equals(typeof matchMedia("(min-width: 1px)").matches, "boolean"), "matches is a boolean");
      test(() => assert_true(matchMedia("screen").matches), "media type");
    JS
  end

  def test_inline_style_reflects_in_computed
    run_css('<!DOCTYPE html><p id="t">x</p>', <<~JS)
      const el = document.getElementById("t");
      test(() => {
        el.style.color = "green";
        assert_equals(getComputedStyle(el).color, "rgb(0, 128, 0)");
      }, "set style.color -> computed");
      test(() => {
        el.style.setProperty("font-size", "10px");
        el.style.setProperty("letter-spacing", "3em");
        assert_equals(getComputedStyle(el).letterSpacing, "30px");
      }, "setProperty em resolves");
    JS
  end

  def test_cssom_stylesheets
    run_css("<!DOCTYPE html><style>p { color: red } a.x { font-size: 12px }</style><p>x</p>", <<~JS)
      const sheet = document.styleSheets[0];
      test(() => assert_equals(document.styleSheets.length, 1), "one stylesheet");
      test(() => assert_equals(sheet.cssRules.length, 2), "two rules");
      test(() => assert_equals(sheet.cssRules[0].selectorText, "p"), "selectorText");
      test(() => assert_equals(sheet.cssRules[1].style.fontSize, "12px"), "rule.style getter");
      test(() => {
        sheet.insertRule("div { color: blue }", 2);
        assert_equals(sheet.cssRules.length, 3);
        assert_equals(sheet.cssRules[2].selectorText, "div");
      }, "insertRule");
      test(() => {
        sheet.deleteRule(0);
        assert_equals(sheet.cssRules.length, 2);
      }, "deleteRule");
    JS
  end

  def test_cssom_mutation_reflects_in_computed
    run_css('<!DOCTYPE html><style>#t { color: red }</style><p id="t">x</p>', <<~JS)
      const el = document.getElementById("t");
      test(() => assert_equals(getComputedStyle(el).color, "rgb(255, 0, 0)"), "before");
      test(() => {
        document.styleSheets[0].cssRules[0].style.color = "green";
        assert_equals(getComputedStyle(el).color, "rgb(0, 128, 0)");
      }, "mutating a rule reflows the cascade");
    JS
  end

  def test_class_based_visibility
    run_css(<<~HTML, <<~JS)
      <!DOCTYPE html><style>.hidden { display: none }</style>
      <p id="a">a</p><p id="b" class="hidden">b</p>
    HTML
      test(() => assert_equals(getComputedStyle(document.getElementById("a")).display, "block"), "visible block");
      test(() => assert_equals(getComputedStyle(document.getElementById("b")).display, "none"), "class hides");
    JS
  end
end
