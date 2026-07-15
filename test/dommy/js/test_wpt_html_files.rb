# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT `html/` files, run through WptRunner. Covers the History interface
# (pushState / replaceState), accessKeyLabel, and ARIA attribute reflection —
# the well-supported corners of the HTML suite.
#
# Omitted: XML/foreign-document corners. (ARIA element-reference reflection —
# including shadow-DOM valid-scope validation — is now supported.)
class Dommy::Js::TestWptHtmlFiles < Minitest::Test
  include Dommy::Js::WptConformance

  HISTORY = "html/browsers/history/the-history-interface"

  wpt_files(
    # --- History interface ----------------------------------------------
    "#{HISTORY}/history_pushstate.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_pushstate_err.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_pushstate_nooptionalparam.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_replacestate.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_replacestate_err.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_replacestate_nooptionalparam.html" => { min_pass: 1, expected: [] },
    "#{HISTORY}/history_state.html" => { min_pass: 1, expected: [] },

    # --- HTML semantics --------------------------------------------------
    "html/semantics/forms/the-button-element/button-type.html" => { min_pass: 2, expected: [] },
    "html/semantics/forms/the-button-element/button-validation.html" => { min_pass: 6, expected: [] },
    "html/semantics/forms/the-textarea-element/cloning-steps.html" => { min_pass: 2, expected: [] },
    "html/semantics/forms/the-input-element/checkbox.html" => { min_pass: 6, expected: [] },
    "html/semantics/forms/the-input-element/minlength.html" => { min_pass: 5, expected: [] },
    "html/semantics/forms/the-input-element/maxlength.html" => { min_pass: 5, expected: [] },
    "html/semantics/forms/the-input-element/input-list.html" => { min_pass: 6, expected: [] },
    "html/semantics/forms/the-input-element/clone.html" => { min_pass: 19, expected: [] },
    "html/semantics/forms/the-select-element/select-value.html" => { min_pass: 4, expected: [] },
    "html/semantics/forms/the-select-element/select-add.html" => { min_pass: 2, expected: [] },
    "html/semantics/forms/the-select-element/select-remove.html" => {
      min_pass: 3,
      # select.remove(index) removes an option; Element.prototype.remove.call
      # (explicit prototype call) on a select is pending.
      expected: ["Element#remove() should work on select elements."]
    },
    "html/semantics/forms/the-option-element/option-text-recurse.html" => { min_pass: 11, expected: [] },
    "html/semantics/forms/the-datalist-element/datalistoptions.html" => { min_pass: 2, expected: [] },
    "html/semantics/forms/the-form-element/form-elements-matches.html" => { min_pass: 2, expected: [] },
    "html/semantics/forms/the-form-element/form-elements-interfaces-01.html" => { min_pass: 3, expected: [] },
    "html/semantics/forms/the-form-element/form-elements-nameditem-01.html" => { min_pass: 3, expected: [] },
    "html/semantics/forms/the-form-element/form-elements-sameobject.html" => { min_pass: 1, expected: [] },
    "html/semantics/forms/the-form-element/form-checkvalidity.html" => { min_pass: 1, expected: [] },
    "html/semantics/forms/the-fieldset-element/HTMLFieldSetElement.html" => { min_pass: 4, expected: [] },
    "html/semantics/forms/the-fieldset-element/fieldset-checkvalidity.html" => { min_pass: 1, expected: [] },
    "html/semantics/forms/the-fieldset-element/fieldset-willvalidate.html" => { min_pass: 1, expected: [] },
    "html/semantics/forms/the-fieldset-element/fieldset-validity.html" => { min_pass: 1, expected: [] },
    "html/semantics/forms/the-fieldset-element/disabled-001.html" => { min_pass: 5, expected: [] },
    "html/semantics/forms/the-select-element/common-HTMLOptionsCollection.html" => { min_pass: 8, expected: [] },
    "html/semantics/forms/the-select-element/common-HTMLOptionsCollection-add.html" => { min_pass: 3, expected: [] },
    "html/semantics/forms/the-select-element/common-HTMLOptionsCollection-namedItem.html" => { min_pass: 6, expected: [] },
    "html/semantics/forms/the-output-element/output-validity.html" => { min_pass: 1, expected: [] },
    "html/semantics/forms/the-label-element/labelable-elements.html" => { min_pass: 26, expected: [] },
    "html/semantics/forms/the-label-element/clicking-interactive-content.html" => { min_pass: 36, expected: [] },
    "html/semantics/forms/the-button-element/button-labels.html" => { min_pass: 1, expected: [] },
    # Constraint validation (ValidityState + checkValidity/reportValidity), now
    # reachable via the :valid/:invalid selectors too.
    "html/semantics/forms/constraints/form-validation-checkValidity.html" => { min_pass: 130, expected: [] },
    "html/semantics/forms/constraints/form-validation-reportValidity.html" => { min_pass: 130, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-valueMissing.html" => { min_pass: 78, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-typeMismatch.html" => { min_pass: 11, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-tooLong.html" => { min_pass: 63, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-tooShort.html" => { min_pass: 63, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-rangeUnderflow.html" => { min_pass: 47, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-rangeOverflow.html" => { min_pass: 49, expected: [] },
    "html/semantics/forms/constraints/form-validation-validity-valid.html" => { min_pass: 35, expected: [] },
    "html/semantics/forms/constraints/form-validation-willValidate.html" => {
      min_pass: 70,
      # <object> is barred from validation; SUBMIT-status willValidate edges.
      expected: ->(name) { name.include?("barred from the constraint") || name.include?("in SUBMIT status") }
    },
    "html/semantics/forms/constraints/form-validation-validity-patternMismatch.html" => {
      min_pass: 74,
      # JS `v`-mode / Unicode-property regex isn't representable in Ruby regex, and
      # the email+multiple pattern path.
      expected: ->(name) { name.include?("regular expression gets ignored") || name.include?("multiple is present") }
    },
    "html/semantics/forms/constraints/form-validation-validity-stepMismatch.html" => {
      min_pass: 27,
      expected: ->(name) { name.include?("very small floating") }
    },
    "html/semantics/forms/constraints/form-validation-validity-badInput.html" => {
      min_pass: 10,
      expected: ->(name) { name.include?("COLOR") }
    },
    "html/semantics/forms/constraints/form-validation-validity-customError.html" => {
      min_pass: 6,
      # customError on <button>/<select> (non-mutable controls).
      expected: ->(name) { name.include?("[button]") || name.include?("[select]") }
    },
    "html/semantics/forms/the-input-element/radio.html" => {
      min_pass: 10,
      # Radio grouping for detached/orphan trees and cross-form-owner isolation
      # isn't modeled (group membership is resolved against the live document).
      expected: [
        "Radio buttons in an orphan tree should make a group",
        "Radio buttons in different groups (because they have different form owners or no form owner) do not affect each other's checkedness"
      ]
    },
    "html/semantics/forms/the-textarea-element/textarea-type.html" => { min_pass: 1, expected: [] },
    "html/semantics/grouping-content/the-li-element/grouping-li.html" => { min_pass: 10, expected: [] },
    "html/semantics/grouping-content/the-ol-element/grouping-ol.html" => { min_pass: 25, expected: [] },
    "html/semantics/grouping-content/the-hr-element/grouping-hr.html" => { min_pass: 1, expected: [] },
    "html/semantics/text-level-semantics/the-time-element/001.html" => { min_pass: 8, expected: [] },

    # --- tabular data (table/tr/tbody DOM APIs, all fully green) ----------
    "html/semantics/tabular-data/the-table-element/caption-methods.html" => { min_pass: 18, expected: [] },
    "html/semantics/tabular-data/the-table-element/createTBody.html" => { min_pass: 15, expected: [] },
    "html/semantics/tabular-data/the-table-element/insertRow-method-01.html" => { min_pass: 1, expected: [] },
    "html/semantics/tabular-data/the-table-element/tBodies.html" => { min_pass: 1, expected: [] },
    "html/semantics/tabular-data/the-table-element/tFoot.html" => { min_pass: 2, expected: [] },
    "html/semantics/tabular-data/the-table-element/tHead.html" => { min_pass: 3, expected: [] },
    "html/semantics/tabular-data/the-table-element/table-rows.html" => { min_pass: 5, expected: [] },
    "html/semantics/tabular-data/the-table-element/delete-caption.html" => { min_pass: 6, expected: [] },
    "html/semantics/tabular-data/the-tr-element/cells.html" => { min_pass: 1, expected: [] },
    "html/semantics/tabular-data/the-tr-element/insertCell.html" => { min_pass: 7, expected: [] },
    "html/semantics/tabular-data/the-tr-element/deleteCell.html" => { min_pass: 6, expected: [] },
    "html/semantics/tabular-data/the-tr-element/rowIndex.html" => { min_pass: 12, expected: [] },
    "html/semantics/tabular-data/the-tr-element/sectionRowIndex.html" => { min_pass: 19, expected: [] },
    "html/semantics/tabular-data/the-tbody-element/rows.html" => { min_pass: 1, expected: [] },
    "html/semantics/tabular-data/the-tbody-element/insertRow.html" => { min_pass: 6, expected: [] },
    "html/semantics/tabular-data/the-tbody-element/deleteRow.html" => { min_pass: 6, expected: [] },
    "html/semantics/tabular-data/the-thead-element/rows.html" => { min_pass: 1, expected: [] },
    "html/semantics/tabular-data/the-tfoot-element/rows.html" => { min_pass: 1, expected: [] },
    "html/semantics/tabular-data/the-caption-element/caption_001.html" => { min_pass: 5, expected: [] },
    "html/semantics/tabular-data/attributes-common-to-td-and-th-elements/cellIndex.html" => { min_pass: 6, expected: [] },
    "html/semantics/grouping-content/the-dl-element/grouping-dl.html" => { min_pass: 1, expected: [] },

    # --- text-level / interactive / embedded -----------------------------
    "html/semantics/interactive-elements/the-details-element/details.html" => { min_pass: 5, expected: [] },
    "html/semantics/text-level-semantics/the-a-element/a.text-getter-01.html" => { min_pass: 6, expected: [] },
    "html/semantics/text-level-semantics/the-a-element/a.text-setter-01.html" => { min_pass: 5, expected: [] },
    "html/semantics/embedded-content/the-img-element/Image-constructor.html" => { min_pass: 5, expected: [] },
    "html/semantics/text-level-semantics/the-a-element/a-stringifier.html" => {
      min_pass: 7,
      # HTMLAnchorElement.prototype.toString.call(nonAnchor) should throw a WebIDL
      # "illegal invocation" TypeError — the bridge doesn't brand-check `this` on
      # host methods.
      expected: [
        "HTMLAnchorElement stringifier 1",
        "HTMLAnchorElement stringifier 2",
        "HTMLAnchorElement stringifier 6",
        "HTMLAnchorElement stringifier 7"
      ]
    },

    # --- HTML DOM --------------------------------------------------------
    "html/dom/access-key-label.html" => { min_pass: 2, expected: [] },
    "html/dom/documents/dom-tree-accessors/document.title-01.html" => { min_pass: 4, expected: [] },
    "html/dom/documents/dom-tree-accessors/document.head-01.html" => { min_pass: 1, expected: [] },
    "html/dom/documents/dom-tree-accessors/document.head-02.html" => { min_pass: 1, expected: [] },
    "html/dom/documents/dom-tree-accessors/document.getElementsByClassName-same.html" => { min_pass: 1, expected: [] },
    "html/dom/documents/dom-tree-accessors/Document.getElementsByClassName-null-undef.html" => { min_pass: 1, expected: [] },
    "html/dom/documents/dom-tree-accessors/Element.getElementsByClassName-null-undef.html" => { min_pass: 1, expected: [] },
    "html/dom/documents/dom-tree-accessors/nameditem-01.html" => {
      min_pass: 6,
      # document named-access doesn't live-update when an element's name attribute
      # changes (a stale name still resolves).
      expected: ["Dynamically updating the name attribute from img elements, should be accessible by values."]
    },
    "html/dom/aria-attribute-reflection.html" => { min_pass: 41, expected: [] },
    "html/dom/aria-element-reflection.html" => { min_pass: 27, expected: [] },
    "html/dom/aria-element-reflection-disconnected.html" => {
      min_pass: 1,
      # Element-reference reflection across disconnection (FrozenArray caching)
      # is not modeled.
      expected: ["Element references should stay valid when content is disconnected (element array)"]
    },
    "html/dom/historical.html" => {
      min_pass: 10,
      # Obsolete <applet>: Dommy still surfaces it as a normal element rather
      # than treating it as unknown/unstyled per the obsolete-features spec.
      expected: [
        "document.all cannot find applet",
        "document cannot find applet",
        "applet is not styled"
      ]
    },

    # --- DOM events: dispatch / propagation / activation -----------------
    # Event dispatch and propagation behavior — the interaction blind spot the
    # coverage survey flagged (notes/test-coverage-strategy.md). These are
    # testdriver-free (pure dispatchEvent/click), so they run without a shim.
    "dom/events/Event-dispatch-bubble-canceled.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-omitted-capture.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-target-removed.html" => { min_pass: 1, expected: [] },
    "dom/events/Event-dispatch-reenter.html" => { min_pass: 1, expected: [] },
    "dom/events/preventDefault-during-activation-behavior.html" => { min_pass: 1, expected: [] },
    "dom/events/EventTarget-dispatchEvent-returnvalue.html" => { min_pass: 2, expected: [] },
    "dom/events/Event-returnValue.html" => { min_pass: 7, expected: [] },
    "dom/events/event-handler-attribute-replace-preserves-passive.html" => { min_pass: 2, expected: [] },
    # A disconnected checkbox/radio toggles on click() but fires input/change
    # only once connected (activation runs in dispatch; see dommy 2f538cf + F2).
    "dom/events/Event-dispatch-detached-input-and-change.html" => { min_pass: 12, expected: [] },
    # At the target, capture-registered listeners run before bubble-registered
    # ones (the listener list is visited once per phase), and a stopPropagation
    # is honored between the two passes — F3/F4.
    "dom/events/Event-dispatch-order-at-target.html" => { min_pass: 1, expected: [] },
    # A listener removed mid-dispatch (or a nested `once` self-removal) is
    # skipped even though it was in the delivery snapshot — F5.
    "dom/events/remove-all-listeners.html" => { min_pass: 2, expected: [] }
  )
end
