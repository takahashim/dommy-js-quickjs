# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT files for the WICG Observable proposal, run through WptRunner. The
# reactive primitive is implemented in JS (dommy's observable_runtime.js:
# Observable / Subscriber / EventTarget.prototype.when), so these files are what
# says whether that implementation is the spec's — and the baseline that a
# refactor of it has to keep.
#
# The expected failures fall into three groups:
#
#   * Detached documents. Dommy has no document detachment, so every subtest
#     that subscribes inside one (the whole of each `.window.js` file below)
#     cannot be represented. Those files are listed at min_pass: 0 rather than
#     dropped, so the day detachment is modeled the gap is visible here.
#   * The microtask in which forEach's visitor-callback rejection lands.
#   * takeUntil's notifier erroring twice: where the second error is reported.
class Dommy::Js::TestWptObservableFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "dom/observable/tentative/observable-catch.any.js" => { min_pass: 9, expected: [] },
    "dom/observable/tentative/observable-constructor.any.js" => { min_pass: 44, expected: [] },
    "dom/observable/tentative/observable-constructor.window.js" => { min_pass: 0, expected: [
      "No observer handlers can be invoked in detached document",
      "Subscriber.error() does not \"report the exception\" even when an `error()` handler is not present, when it is invoked in a detached document",
      "Cannot subscribe to an Observable in a detached document",
      "Observable from EventTarget does not get notified for events in detached documents",
    ] },
    "dom/observable/tentative/observable-drop.any.js" => { min_pass: 7, expected: [] },
    "dom/observable/tentative/observable-event-target.any.js" => { min_pass: 3, expected: [] },
    "dom/observable/tentative/observable-event-target.window.js" => { min_pass: 2, expected: [] },
    "dom/observable/tentative/observable-every.any.js" => { min_pass: 10, expected: [] },
    "dom/observable/tentative/observable-filter.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-finally.any.js" => { min_pass: 10, expected: [] },
    "dom/observable/tentative/observable-find.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-first.any.js" => { min_pass: 5, expected: [] },
    "dom/observable/tentative/observable-flatMap.any.js" => { min_pass: 7, expected: [] },
    "dom/observable/tentative/observable-forEach.any.js" => { min_pass: 5, expected: [
      "forEach visitor callback rejection microtask ordering",
    ] },
    "dom/observable/tentative/observable-forEach.window.js" => { min_pass: 0, expected: [
      "forEach()'s internal observer's next steps do not crash in a detached document",
      "forEach()'s internal observer's next steps do not crash when visitor callback detaches the document",
    ] },
    "dom/observable/tentative/observable-from.any.js" => { min_pass: 48, expected: [] },
    "dom/observable/tentative/observable-inspect.any.js" => { min_pass: 13, expected: [] },
    "dom/observable/tentative/observable-last.any.js" => { min_pass: 5, expected: [] },
    "dom/observable/tentative/observable-map.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-map.window.js" => { min_pass: 0, expected: [
      "map()'s internal observer's next steps do not crash in a detached document",
    ] },
    "dom/observable/tentative/observable-reduce.any.js" => { min_pass: 8, expected: [] },
    "dom/observable/tentative/observable-some.any.js" => { min_pass: 7, expected: [] },
    "dom/observable/tentative/observable-switchMap.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-take.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-takeUntil.any.js" => { min_pass: 11, expected: [
      "takeUntil: notifier calls `Subscriber#error()` twice; second goes to global error handler",
    ] },
    "dom/observable/tentative/observable-takeUntil.window.js" => { min_pass: 0, expected: [
      "takeUntil(): notifier Observable detaches document before source Observable would be subscribed to",
      "takeUntil(): Source and notifier internal observers do not crash in a detached document",
    ] },
    "dom/observable/tentative/observable-toArray.any.js" => { min_pass: 6, expected: [] },
  )
end
