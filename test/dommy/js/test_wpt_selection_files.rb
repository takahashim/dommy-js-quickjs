# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT selection/ files, run through WptRunner: the Selection API that needs
# no rendering and no user input — addRange, collapse / setPosition, extend,
# setBaseAndExtent, selectAllChildren, removeRange / removeAllRanges,
# collapseToStart / collapseToEnd, getRangeAt, getSelection, type, isCollapsed,
# and the tentative files on ranges that leave the document and on shadow DOM.
# Vendored from web-platform-tests c913d93adb99. Left out: files that need
# layout, testdriver input, contenteditable, or script run inside a dynamically
# created iframe (deleteFromDocument.html).
#
# Dommy follows these since its Selection rework, which dommy 0.11.0 predates.
# CI resolves the released gem, so the suite skips when the loaded Dommy has no
# Selection#get_composed_ranges.
class Dommy::Js::TestWptSelectionFiles < Minitest::Test
  include Dommy::Js::WptConformance

  def setup
    super
    return if Dommy::Selection.method_defined?(:get_composed_ranges)

    skip "needs the Selection API rework, which dommy 0.11.0 predates"
  end

  wpt_files(
    "selection/addRange-00.html" => { min_pass: 1624, expected: [] },
    "selection/addRange-04.html" => { min_pass: 1624, expected: [] },
    "selection/addRange-08.html" => { min_pass: 232, expected: [] },
    "selection/addRange-12.html" => { min_pass: 928, expected: [] },
    "selection/addRange-16.html" => { min_pass: 1276, expected: [] },
    "selection/addRange-20.html" => { min_pass: 928, expected: [] },
    "selection/addRange-24.html" => { min_pass: 928, expected: [] },
    "selection/addRange-28.html" => { min_pass: 1624, expected: [] },
    "selection/addRange-32.html" => { min_pass: 1276, expected: [] },
    "selection/addRange-36.html" => { min_pass: 1624, expected: [] },
    "selection/addRange-40.html" => { min_pass: 232, expected: [] },
    "selection/addRange-44.html" => { min_pass: 232, expected: [] },
    "selection/addRange-48.html" => { min_pass: 232, expected: [] },
    "selection/addRange-52.html" => { min_pass: 232, expected: [] },
    "selection/addRange-56.html" => { min_pass: 116, expected: [] },
    "selection/addRange.htm" => { min_pass: 1, expected: [] },
    "selection/collapse-00.html" => { min_pass: 2655, expected: [] },
    "selection/collapse-15.html" => { min_pass: 2655, expected: [] },
    "selection/collapse-30.html" => { min_pass: 5133, expected: [] },
    "selection/collapse-45.html" => { min_pass: 2655, expected: [] },
    "selection/collapse.htm" => { min_pass: 1, expected: [] },
    "selection/collapseToStartEnd.html" => { min_pass: 57, expected: [] },
    "selection/extend-00.html" => { min_pass: 2024, expected: [] },
    "selection/extend-20.html" => { min_pass: 2376, expected: [] },
    "selection/extend-40.html" => { min_pass: 176, expected: [] },
    "selection/extend-exception.html" => { min_pass: 1, expected: [] },
    "selection/getRangeAt.html" => { min_pass: 4, expected: [] },
    "selection/getSelection.html" => { min_pass: 18, expected: [] },
    "selection/isCollapsed.html" => { min_pass: 29, expected: [] },
    "selection/move-selection-range-into-different-root.tentative.html" => { min_pass: 16, expected: [] },
    "selection/removeAllRanges.html" => { min_pass: 116, expected: [] },
    "selection/removeRange.html" => { min_pass: 29, expected: [] },
    "selection/selectAllChildren.html" => { min_pass: 2242, expected: [] },
    "selection/setBaseAndExtent.html" => { min_pass: 120, expected: [] },
    "selection/shadow-dom/tentative/Selection-direction.html" => {
      min_pass: 3,
      expected: [
        # These reach the fixture through window named properties (`host`, `container`),
        # which Dommy does not expose; the two that cross shadow boundaries also need a
        # composed selection (see Selection-getComposedRanges).
        "direction returns \"forward\" when there is a forward selection in the shadow tree",
        "direction returns \"backward\" when there is a backward selection in the shadow tree",
        "direction returns \"forward\" when there is a forward selection that crosses shadow boundaries",
        "direction returns \"backward\" when there is a forward selection that crosses shadow boundaries"
      ]
    },
    "selection/shadow-dom/tentative/Selection-getComposedRanges.html" => {
      min_pass: 10,
      expected: [
        # A selection whose ends sit in different trees would need a composed selection
        # that keeps both ends. Dommy's range collapses at the anchor there, as Chrome's
        # and Firefox's do.
        "getComposedRanges a sequence with a static range that crosses shadow boundaries when there is a forward selection that crosses shadow boundaries and the shadow tree is specified as an argument",
        "getComposedRanges returns a sequence with a static range without rescoping when there is a selection in an outer shadow tree and the inner shadow tree is specified as an argument"
      ]
    },
    "selection/type.html" => { min_pass: 29, expected: [] }
  )
end
