# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT CSS test files, run through the browser-true WptRunner with a
# documented expected-failures baseline (see WptConformance). Expected failures
# fall into two buckets: layout — resolved/used values that need a box tree
# (Dommy is layout-less) — and unimplemented/edge CSSOM.
class Dommy::Js::TestWptCssFiles < Minitest::Test
  include Dommy::Js::WptConformance

  # All getComputedStyle-pseudo failures are box/layout dependent: width
  # resolution and probing pseudo-elements that only exist once a box exists.
  LAYOUT_PSEUDO = lambda do |name|
    name.include?("width") ||
      name.include?("pseudo-element") ||
      name.include?("display: contents") ||
      name.include?("CSSStyleDeclaration is immutable") ||
      name.include?("full range of CSS syntax") ||
      name.start_with?("Unknown pseudo-element", "::file-selector-button", "Item-based")
  end

  # hsl() stragglers: calc()/sign()/container-query units inside the color
  # function — math Dommy doesn't resolve in color channels.
  CALC_IN_COLOR = ->(name) { name.include?("calc(") }

  # var() argument syntaxes Dommy doesn't reject (`var(--x ())`).
  #
  # Upstream's 2026-09 revision flipped these cases: a `var()` whose argument is
  # not a custom property name is no longer invalid at parse time, so the same
  # declarations it used to require be dropped it now requires be kept. Dommy
  # rejects them either way, which is why both directions are expected here.
  # Fixing the parser turns eight of these into passes (see the dommy notes).
  VAR_INVALID_SYNTAX = lambda do |name|
    name.include?("should not set") ||
      (name.include?("should set the property value") && name.match?(/var\(\{|var\(--x ?\(/))
  end

  wpt_files(
    "css/cssom/cssom-setProperty-shorthand.html" => { min_pass: 76, expected: [] },
    "css/css-syntax/declarations-trim-whitespace.html" => { min_pass: 9, expected: [] },
    "css/css-variables/var-parsing.html" => { min_pass: 3, expected: VAR_INVALID_SYNTAX },
    "css/css-variables/variable-cycles.html" => { min_pass: 11, expected: [] },
    "css/selectors/child-indexed-pseudo-class.html" => { min_pass: 54, expected: [] },
    "css/selectors/has-basic.html" => { min_pass: 18, expected: [] },
    "css/selectors/pseudo-enabled-disabled.html" => { min_pass: 4, expected: [] },
    # :is()/:where() accept an empty (forgiving) selector list -> matches nothing.
    "css/selectors/is-where-basic.html" => { min_pass: 15, expected: [] },
    "css/selectors/is-where-not.html" => { min_pass: 18, expected: [] },
    "css/selectors/is-where-error-recovery.html" => { min_pass: 1, expected: [] },
    "css/selectors/is-nested.html" => { min_pass: 2, expected: [] },
    "css/selectors/not-complex.html" => { min_pass: 20, expected: [] },
    "css/selectors/first-child.html" => { min_pass: 5, expected: [] },
    "css/selectors/last-child.html" => { min_pass: 5, expected: [] },
    "css/selectors/only-child.html" => { min_pass: 5, expected: [] },
    "css/selectors/scope-selector.html" => {
      min_pass: 2,
      # querySelector(":scope") on a document should return the document element.
      expected: ["querySelector() with \":scope\" should return the document element, if present in the subtree"]
    },
    "css/css-color/parsing/color-computed.html" => { min_pass: 16, expected: [] },
    "css/css-color/parsing/color-computed-hex-color.html" => { min_pass: 6, expected: [] },
    "css/css-color/parsing/color-computed-hsl.html" => { min_pass: 3735, expected: CALC_IN_COLOR, heavy: true },
    "css/cssom/CSSStyleSheet.html" => {
      min_pass: 14,
      expected: [
        "addRule with @media rule",                         # CSSMediaRule JS constructor
        "addRule with #foo selectors",                      # verbatim (not re-serialized) cssText
        'addRule with no argument adds "undefined" selector'
      ]
    },
    "css/cssom/MediaList.html" => { min_pass: 1, expected: [] },
    "css/cssom/getComputedStyle-detached-subtree.html" => { min_pass: 1, expected: [] },
    "css/cssom/getComputedStyle-pseudo.html" => { min_pass: 4, expected: LAYOUT_PSEUDO },
    "css/cssom/css-style-attribute-modifications.html" => { min_pass: 1, expected: [] },
    "css/cssom/css-style-attr-decl-block.html" => {
      min_pass: 5,
      # A no-op declaration change (removing an absent property / setting an
      # invalid value that's dropped) should queue no mutation record — Dommy
      # doesn't validate CSS values or detect the no-op. Base-URL-change
      # reflection needs navigation.
      expected: [
        "Removing non-existing property or setting invalid value on CSS declaration block shouldn't queue mutation record",
        "Changes to CSS declaration block after a base URL change"
      ]
    }
  )
end
