# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_runner"

# Runs the vendored real WPT CSS test files through WptRunner — the browser-true
# path (the file is the document, its <script> tags boot through ScriptBoot,
# testharness.js + helpers served by WptResources). Each file's failing
# subtests must be a subset of the documented EXPECTED_FAILURES, so a new
# regression fails the build while a future fix (a known-failing subtest that
# starts passing) is tolerated.
#
# Expected failures fall into two buckets:
#   * layout — resolved/used values that need a box tree (Dommy is layout-less)
#   * unimplemented CSSOM — legacy/edge interface members Dommy doesn't model
class Dommy::Js::TestWptCssFiles < Minitest::Test
  # file (relative to the vendored WPT root) => { min_pass:, expected: [names] }
  EXPECTED = {
    "css/cssom/CSSStyleSheet.html" => {
      min_pass: 14,
      expected: [
        # CSSOM rule subclasses aren't exposed as JS constructors
        "addRule with @media rule",
        # addRule rule text isn't re-serialized (Dommy keeps verbatim cssText)
        "addRule with #foo selectors",
        'addRule with no argument adds "undefined" selector'
      ]
    },
    "css/cssom/MediaList.html" => {
      min_pass: 0,
      expected: ["CSSOM - MediaList interface"] # MediaList interface not modelled
    },
    "css/cssom/getComputedStyle-detached-subtree.html" => {
      min_pass: 1,
      expected: [] # fully passing
    },
    "css/css-syntax/declarations-trim-whitespace.html" => { min_pass: 9, expected: [] },
    "css/selectors/child-indexed-pseudo-class.html" => { min_pass: 54, expected: [] },
    "css/css-color/parsing/color-computed.html" => { min_pass: 16, expected: [] },
    "css/css-color/parsing/color-computed-hex-color.html" => { min_pass: 6, expected: [] },
    "css/css-color/parsing/color-computed-hsl.html" => {
      min_pass: 3735,
      # the stragglers are calc()/sign()/container-query units *inside* the
      # color function — math resolution Dommy doesn't do in color channels.
      expected: :calc_in_color
    },
    "css/cssom/getComputedStyle-pseudo.html" => {
      min_pass: 4,
      # width resolution + pseudo-element box probing all need layout / boxes.
      expected: :layout_pseudo
    }
  }.freeze

  def setup
    skip "WPT not vendored" unless Dommy::Js::WptRunner.available?
  end

  EXPECTED.each do |file, spec|
    define_method("test_#{file.gsub(/[^a-z0-9]+/i, '_')}") do
      results = Dommy::Js::WptRunner.run(file)
      refute_empty results, "#{file}: harness produced no subtests"

      passed = results.count(&:pass?)
      assert_operator passed, :>=, spec[:min_pass],
        "#{file}: #{passed} pass, below baseline #{spec[:min_pass]} (a regression)"

      failing = results.reject(&:pass?).map(&:name)
      unexpected = failing.reject { |name| expected?(spec[:expected], name) }
      assert_empty unexpected, "#{file}: unexpected (new) failures:\n  #{unexpected.join("\n  ")}"
    end
  end

  private

  def expected?(expected, name)
    return layout_pseudo?(name) if expected == :layout_pseudo
    return name.include?("calc(") if expected == :calc_in_color

    expected.include?(name)
  end

  # The getComputedStyle-pseudo failures are all box/layout dependent: width
  # resolution (no layout) and probing pseudo-elements that only exist once a
  # box is generated (which Dommy doesn't do).
  def layout_pseudo?(name)
    name.include?("width") ||
      name.include?("pseudo-element") ||
      name.include?("display: contents") ||
      name.include?("CSSStyleDeclaration is immutable") ||
      name.include?("full range of CSS syntax") ||
      name.start_with?("Unknown pseudo-element", "::file-selector-button", "Item-based")
  end
end
