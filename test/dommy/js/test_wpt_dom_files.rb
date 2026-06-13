# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT DOM `.any.js` / `.window.js` / `.html` files, run through WptRunner.
# Covers the well-supported DOM areas — AbortSignal, collections, token lists,
# events, ranges, traversal, and the high-pass node files. The few remaining
# expected failures stem from two out-of-scope limitations:
#
#   * No XML documents — Dommy is HTML-only, so the xmlDoc cases (created via
#     implementation.createDocument) in Range-commonAncestorContainer can't be
#     represented. (Second HTML documents via createHTMLDocument *are*
#     supported, and their NodeIterator pre-removing steps now fire correctly.)
#   * The document node isn't modeled as documentElement's parent
#     (`documentElement.parentNode === document` is false), so a NodeFilter that
#     re-enters a *document-rooted* walker never reaches the filter — the
#     re-entrancy guard itself is implemented and unit-tested in dommy.
class Dommy::Js::TestWptDomFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    # --- abort -----------------------------------------------------------
    "dom/abort/AbortSignal.any.js" => { min_pass: 2, expected: [] },
    "dom/abort/abort-signal-any.any.js" => { min_pass: 14, expected: [] },
    "dom/abort/event.any.js" => { min_pass: 16, expected: [] },
    "dom/abort/timeout.any.js" => { min_pass: 3, expected: [] },

    # --- collections -----------------------------------------------------
    "dom/collections/HTMLCollection-delete.html" => { min_pass: 4, expected: [] },
    "dom/collections/HTMLCollection-empty-name.html" => { min_pass: 7, expected: [] },
    "dom/collections/HTMLCollection-iterator.html" => { min_pass: 6, expected: [] },
    "dom/collections/HTMLCollection-live-mutations.window.js" => { min_pass: 5, expected: [] },
    "dom/collections/HTMLCollection-own-props.html" => { min_pass: 8, expected: [] },
    "dom/collections/HTMLCollection-supported-property-indices.html" => { min_pass: 7, expected: [] },
    "dom/collections/HTMLCollection-supported-property-names.html" => { min_pass: 6, expected: [] },
    "dom/collections/domstringmap-supported-property-names.html" => { min_pass: 5, expected: [] },
    "dom/collections/namednodemap-supported-property-names.html" => { min_pass: 3, expected: [] },

    # --- lists (DOMTokenList) -------------------------------------------
    "dom/lists/DOMTokenList-Iterable.html" => { min_pass: 6, expected: [] },
    "dom/lists/DOMTokenList-coverage-for-attributes.html" => { min_pass: 175, expected: [] },
    "dom/lists/DOMTokenList-iteration.html" => { min_pass: 6, expected: [] },
    "dom/lists/DOMTokenList-stringifier.html" => { min_pass: 1, expected: [] },
    "dom/lists/DOMTokenList-value.html" => { min_pass: 1, expected: [] },

    # --- events ----------------------------------------------------------
    "dom/events/AddEventListenerOptions-once.any.js" => { min_pass: 4, expected: [] },
    "dom/events/CustomEvent.html" => { min_pass: 3, expected: [] },
    "dom/events/Event-constructors.any.js" => { min_pass: 14, expected: [] },
    "dom/events/Event-dispatch-bubbles-false.html" => { min_pass: 5, expected: [] },
    "dom/events/Event-dispatch-bubbles-true.html" => { min_pass: 5, expected: [] },
    "dom/events/Event-initEvent.html" => { min_pass: 12, expected: [] },
    "dom/events/Event-isTrusted.any.js" => { min_pass: 1, expected: [] },
    "dom/events/Event-propagation.html" => { min_pass: 7, expected: [] },
    "dom/events/Event-stopImmediatePropagation.html" => { min_pass: 1, expected: [] },
    "dom/events/EventListenerOptions-capture.html" => { min_pass: 4, expected: [] },
    "dom/events/EventTarget-add-remove-listener.any.js" => { min_pass: 1, expected: [] },

    # --- nodes (high-pass, HTML-only subset) -----------------------------
    "dom/nodes/Element-classlist.html" => { min_pass: 1420, expected: [] },
    "dom/nodes/Element-firstElementChild.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-getElementsByClassName.html" => { min_pass: 3, expected: [] },
    "dom/nodes/Element-tagName.html" => { min_pass: 6, expected: [] },
    "dom/nodes/Node-childNodes.html" => { min_pass: 6, expected: [] },
    "dom/nodes/Node-cloneNode.html" => {
      min_pass: 119,
      # cloneNode of elements whose dedicated interface Dommy doesn't model as a
      # distinct class (canvas/col/datalist/fieldset/…), plus createElementNS and
      # XML-document factories (createProcessingInstruction / createDocument).
      expected: [
        "createElement(canvas)", "createElement(col)", "createElement(colgroup)",
        "createElement(datalist)", "createElement(dir)", "createElement(dl)",
        "createElement(fieldset)", "createElement(font)", "createElement(frame)",
        "createElement(frameset)", "createElement(param)",
        "createElementNS HTML", "createElementNS non-HTML",
        "createProcessingInstruction",
        "implementation.createDocumentType", "implementation.createDocument"
      ]
    },
    "dom/nodes/Node-contains.html" => { min_pass: 1482, expected: [] },
    "dom/nodes/Node-isEqualNode.html" => { min_pass: 9, expected: [] },
    "dom/nodes/Node-isSameNode.html" => {
      min_pass: 8,
      # Document identity comparison (no second-document reference to compare).
      expected: ["documents should be compared on reference"]
    },
    "dom/nodes/Node-nodeName.html" => { min_pass: 6, expected: [] },
    "dom/nodes/ParentNode-children.html" => { min_pass: 1, expected: [] },
    "dom/nodes/ParentNode-querySelector-case-insensitive.html" => { min_pass: 2, expected: [] },
    "dom/nodes/ParentNode-querySelector-scope.html" => { min_pass: 4, expected: [] },
    "dom/nodes/ParentNode-querySelectors-space-and-dash-attribute-value.html" => { min_pass: 2, expected: [] },

    # --- ranges ----------------------------------------------------------
    "dom/ranges/Range-attributes.html" => { min_pass: 1, expected: [] },
    "dom/ranges/Range-cloneRange.html" => { min_pass: 62, expected: [] },
    "dom/ranges/Range-collapse.html" => { min_pass: 186, expected: [] },
    "dom/ranges/Range-commonAncestorContainer.html" => {
      min_pass: 61,
      expected: [
        # foreign (XML/XHTML) documents are out of scope (HTML-only).
        "30: range [foreignDoc, 1, foreignComment, 2]",
        "32: range [xmlDoc, 1, xmlComment, 0]"
      ]
    },
    "dom/ranges/Range-constructor.html" => { min_pass: 1, expected: [] },
    "dom/ranges/Range-detach.html" => { min_pass: 1, expected: [] },
    "dom/ranges/Range-stringifier.html" => { min_pass: 5, expected: [] },

    # --- traversal -------------------------------------------------------
    "dom/traversal/NodeFilter-constants.html" => { min_pass: 2, expected: [] },
    "dom/traversal/NodeIterator.html" => {
      min_pass: 765,
      # Re-entrant filter on a document-rooted iterator never advances past the
      # document node (documentElement.parentNode !== document), so the guard
      # never fires here. See dommy test_tree_walker reentrancy coverage.
      expected: ["Recursive filters need to throw"]
    },
    "dom/traversal/NodeIterator-removal.html" => { min_pass: 16, expected: [] },
    "dom/traversal/TreeWalker-acceptNode-filter.html" => { min_pass: 12, expected: [] },
    "dom/traversal/TreeWalker-basic.html" => { min_pass: 6, expected: [] },
    "dom/traversal/TreeWalker-currentNode.html" => { min_pass: 4, expected: [] },
    "dom/traversal/TreeWalker-previousNodeLastChildReject.html" => { min_pass: 1, expected: [] },
    "dom/traversal/TreeWalker-previousSiblingLastChildSkip.html" => { min_pass: 1, expected: [] },
    "dom/traversal/TreeWalker-traversal-reject.html" => { min_pass: 6, expected: [] },
    "dom/traversal/TreeWalker-traversal-skip-most.html" => { min_pass: 2, expected: [] },
    "dom/traversal/TreeWalker-traversal-skip.html" => { min_pass: 6, expected: [] },
    "dom/traversal/TreeWalker-walking-outside-a-tree.html" => { min_pass: 1, expected: [] },
    "dom/traversal/TreeWalker.html" => {
      min_pass: 760,
      expected: ["Recursive filters need to throw"]
    }
  )
end
