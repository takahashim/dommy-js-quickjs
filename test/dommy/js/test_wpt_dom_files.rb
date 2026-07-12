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
    "dom/events/Event-cancelBubble.html" => { min_pass: 8, expected: [] },
    "dom/events/Event-constants.html" => { min_pass: 4, expected: [] },
    "dom/events/Event-constructors.any.js" => { min_pass: 14, expected: [] },
    "dom/events/Event-defaultPrevented.html" => { min_pass: 8, expected: [] },
    "dom/events/Event-defaultPrevented-after-dispatch.html" => { min_pass: 2, expected: [] },
    "dom/events/Event-dispatch-bubbles-false.html" => { min_pass: 5, expected: [] },
    "dom/events/Event-dispatch-bubbles-true.html" => { min_pass: 5, expected: [] },
    "dom/events/Event-dispatch-detached-click.html" => { min_pass: 2, expected: [] },
    "dom/events/Event-dispatch-multiple-cancelBubble.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-multiple-stopPropagation.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-order.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-propagation-stopped.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-target-moved.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-initEvent.html" => { min_pass: 12, expected: [] },
    "dom/events/Event-isTrusted.any.js" => { min_pass: 1, expected: [] },
    "dom/events/Event-propagation.html" => { min_pass: 7, expected: [] },
    "dom/events/Event-stopImmediatePropagation.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-type.html" => { min_pass: 3, expected: [] },
    "dom/events/Event-type-empty.html" => { min_pass: 2, expected: [] },
    "dom/events/EventListenerOptions-capture.html" => { min_pass: 4, expected: [] },
    "dom/events/EventTarget-add-remove-listener.any.js" => { min_pass: 1, expected: [] },

    # --- nodes (high-pass, HTML-only subset) -----------------------------
    "dom/nodes/Element-classlist.html" => { min_pass: 1420, expected: [] },
    "dom/nodes/Node-appendChild.html" => {
      min_pass: 8,
      # `window.frames` (browsing-context container reflection) isn't modeled.
      expected: ["Appending a document", "Adopting an orphan", "Adopting a non-orphan"]
    },
    "dom/nodes/Comment-constructor.html" => {
      min_pass: 15,
      # Only the cross-global ownerDocument case remains (WptRunner has no second
      # realm whose Comment constructor binds that realm's document).
      expected: ["new Comment() should get the correct ownerDocument across globals"]
    },
    "dom/nodes/DocumentFragment-constructor.html" => { min_pass: 2, expected: [] },
    "dom/nodes/Document-getElementsByClassName.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Document-implementation.html" => { min_pass: 2, expected: [] },
    "dom/nodes/DOMImplementation-hasFeature.html" => { min_pass: 137, expected: [] },
    "dom/nodes/DOMImplementation-createDocumentType.html" => {
      min_pass: 80,
      # Qualified-name QName validation isn't enforced for createDocumentType.
      expected: [
        "createDocumentType(\"edi:>\", \"\", \"\") should throw INVALID_CHARACTER_ERR",
        "createDocumentType(\"edi:a \", \"\", \"\") should throw INVALID_CHARACTER_ERR"
      ]
    },
    "dom/nodes/Element-childElementCount.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-firstElementChild.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-getElementsByClassName.html" => { min_pass: 3, expected: [] },
    "dom/nodes/Element-hasAttribute.html" => { min_pass: 2, expected: [] },
    "dom/nodes/Element-hasAttributes.html" => { min_pass: 2, expected: [] },
    "dom/nodes/Element-lastElementChild.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-nextElementSibling.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-previousElementSibling.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-siblingElement-null.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-tagName.html" => { min_pass: 6, expected: [] },
    "dom/nodes/attributes-namednodemap.html" => {
      min_pass: 7,
      # NamedNodeMap named-property set vs. method-name shadowing edge.
      expected: ["setNamedItem and removeNamedItem on `attributes` should not interfere with existing method names"]
    },
    "dom/nodes/getElementsByClassName-empty-set.html" => { min_pass: 3, expected: [] },
    "dom/nodes/Node-compareDocumentPosition.html" => { min_pass: 1444, expected: [] },
    "dom/nodes/getElementsByClassName-01.htm" => { min_pass: 1, expected: [] },
    "dom/nodes/getElementsByClassName-02.htm" => { min_pass: 1, expected: [] },
    "dom/nodes/Node-childNodes.html" => { min_pass: 6, expected: [] },
    "dom/nodes/Node-nodeValue.html" => { min_pass: 7, expected: [] },
    "dom/nodes/Node-isConnected.html" => { min_pass: 2, expected: [] },
    "dom/nodes/Element-childElement-null.html" => { min_pass: 1, expected: [] },
    "dom/nodes/getElementsByClassName-32.html" => { min_pass: 4, expected: [] },
    "dom/nodes/Element-closest.html" => {
      min_pass: 27,
      # Remaining selector-engine edges: the :invalid form-validity pseudo, and
      # :scope nested inside :has().
      expected: [
        "Element.closest with context node 'test11' and selector ':invalid'",
        "Element.closest with context node 'test4' and selector ':has(> :scope)'"
      ]
    },
    "dom/nodes/Element-removeAttributeNS.html" => { min_pass: 1, expected: [] },
    "dom/nodes/Element-setAttribute-crbug-1138487.html" => { min_pass: 1, expected: [] },
    "dom/nodes/attributes.html" => { min_pass: 67, expected: [] },
    "dom/nodes/Node-parentNode.html" => {
      min_pass: 4,
      # A node in a removed iframe's document — iframe subframe lifecycle is out
      # of scope (the iframe pipeline is deliberately not unified; see the
      # navigation work notes).
      expected: ["Removed iframe"]
    },
    # ChildNode before/after/replaceWith: the shared Internal::ChildNode
    # implementation follows the WHATWG "viable previous/next sibling" algorithm
    # (skip argument nodes, resolve the reference child after detaching, insert
    # forward), and the JS bridge does the `(Node or DOMString)...` union
    # coercion (null -> "null", undefined -> "undefined") before args cross.
    "dom/nodes/ChildNode-before.html" => { min_pass: 45, expected: [] },
    "dom/nodes/ChildNode-after.html" => { min_pass: 45, expected: [] },
    "dom/nodes/ChildNode-replaceWith.html" => { min_pass: 33, expected: [] },
    # ParentNode append/prepend/replaceChildren, including the WHATWG step-6
    # Document-parent pre-insertion hierarchy constraints (single element, no
    # text, doctype placement) enforced in Document#ensure_document_insertion_validity!.
    "dom/nodes/ParentNode-append.html" => { min_pass: 25, expected: [] },
    "dom/nodes/ParentNode-prepend.html" => { min_pass: 22, expected: [] },
    "dom/nodes/ParentNode-replaceChildren.html" => {
      min_pass: 30,
      # A cloned doctype re-inserted via replaceChildren gets a fresh wrapper
      # rather than the passed-in one (DocumentType wrapper-identity gap), so
      # the assert_array_equals identity check fails.
      expected: ["Document.replaceChildren() with a doctype, replacing an existing doctype and element."]
    },
    "dom/nodes/Node-insertBefore.html" => {
      min_pass: 39,
      # WebIDL requires the reference-child argument to be Node/null/undefined,
      # else TypeError; Dommy doesn't yet type-check the second argument.
      expected: ["Calling insertBefore with second argument missing, or other than Node, null, or undefined, must throw TypeError."]
    },
    # replaceChild: leaf-parent HierarchyRequestError ordering, document step-6
    # constraints (excluding the replaced node from the "already has" counts),
    # the reference-child==new-child anchor advance, and cross-document doctype
    # adoption (re-created in the destination backend, wrapper reseated).
    "dom/nodes/Node-replaceChild.html" => { min_pass: 29, expected: [] },
    "dom/nodes/Node-removeChild.html" => { min_pass: 28, expected: [] },
    # CharacterData: offsets/counts are WebIDL unsigned long (ToUint32 wrap) and
    # measured in UTF-16 code units (astral chars count as 2); null coerces to
    # "null"; substringData/appendData enforce their required-argument arity.
    "dom/nodes/CharacterData-data.html" => { min_pass: 16, expected: [] },
    "dom/nodes/CharacterData-appendData.html" => { min_pass: 14, expected: [] },
    "dom/nodes/CharacterData-insertData.html" => { min_pass: 18, expected: [] },
    "dom/nodes/CharacterData-deleteData.html" => { min_pass: 18, expected: [] },
    "dom/nodes/CharacterData-replaceData.html" => { min_pass: 34, expected: [] },
    "dom/nodes/CharacterData-substringData.html" => { min_pass: 28, expected: [] },
    "dom/nodes/Text-splitText.html" => { min_pass: 6, expected: [] },
    # ChildNode#remove is void -> returns undefined (not null); createComment /
    # createTextNode coerce a null argument to the string "null".
    "dom/nodes/CharacterData-remove.html" => { min_pass: 12, expected: [] },
    "dom/nodes/Element-remove.html" => { min_pass: 4, expected: [] },
    "dom/nodes/Document-createComment.html" => { min_pass: 6, expected: [] },
    "dom/nodes/Document-createTextNode.html" => { min_pass: 6, expected: [] },
    # normalize() now merges adjacent Text descendants (preserving the first
    # node's identity) recursively on DocumentFragment too, not just Element.
    "dom/nodes/Node-normalize.html" => { min_pass: 4, expected: [] },
    "dom/nodes/DocumentType-literal.html" => { min_pass: 1, expected: [] },
    # adoptNode: rejecting a Document (NotSupportedError) works; the two failures
    # are elements with XML-invalid names (`x<`, `:good:times:`) being adopted
    # into an XML document, which Makiri's XML backend rejects (name strictness).
    "dom/nodes/Document-adoptNode.html" => {
      min_pass: 2,
      expected: [
        "Adopting an Element called 'x<' should work.",
        "Adopting an Element called ':good:times:' should work."
      ]
    },
    "dom/nodes/Node-cloneNode.html" => { min_pass: 135, expected: [] },
    "dom/nodes/Node-contains.html" => { min_pass: 1482, expected: [] },
    "dom/nodes/Node-isEqualNode.html" => { min_pass: 9, expected: [] },
    "dom/nodes/Node-isSameNode.html" => {
      min_pass: 8,
      # Document identity comparison (no second-document reference to compare).
      expected: ["documents should be compared on reference"]
    },
    "dom/nodes/Node-nodeName.html" => { min_pass: 6, expected: [] },
    "dom/nodes/Text-constructor.html" => {
      min_pass: 15,
      expected: ["new Text() should get the correct ownerDocument across globals"]
    },
    "dom/nodes/ParentNode-children.html" => { min_pass: 1, expected: [] },
    "dom/nodes/ParentNode-querySelector-case-insensitive.html" => { min_pass: 2, expected: [] },
    "dom/nodes/ParentNode-querySelector-scope.html" => { min_pass: 4, expected: [] },
    "dom/nodes/ParentNode-querySelectors-space-and-dash-attribute-value.html" => { min_pass: 2, expected: [] },

    # --- ranges ----------------------------------------------------------
    "dom/ranges/Range-attributes.html" => { min_pass: 1, expected: [] },
    "dom/ranges/Range-cloneRange.html" => { min_pass: 62, expected: [] },
    "dom/ranges/Range-collapse.html" => { min_pass: 186, expected: [] },
    "dom/ranges/Range-comparePoint.html" => { min_pass: 5580, expected: [], heavy: true },
    "dom/ranges/Range-compareBoundaryPoints.html" => { min_pass: 9313, expected: [], heavy: true },
    "dom/ranges/Range-intersectsNode.html" => { min_pass: 2356, expected: [] },
    "dom/ranges/Range-isPointInRange.html" => { min_pass: 5733, expected: [], heavy: true },
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
