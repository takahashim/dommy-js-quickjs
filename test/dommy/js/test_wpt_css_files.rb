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
  VAR_INVALID_SYNTAX = ->(name) { name.include?("should not set") }

  wpt_files(
    "css/cssom/cssom-setProperty-shorthand.html" => { min_pass: 76, expected: [] },
    "css/css-syntax/declarations-trim-whitespace.html" => { min_pass: 9, expected: [] },
    "css/css-variables/var-parsing.html" => { min_pass: 3, expected: VAR_INVALID_SYNTAX },
    "css/css-variables/variable-cycles.html" => { min_pass: 11, expected: [] },
    "css/selectors/child-indexed-pseudo-class.html" => { min_pass: 54, expected: [] },
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
    "css/cssom/getComputedStyle-pseudo.html" => { min_pass: 4, expected: LAYOUT_PSEUDO }
  )
end
