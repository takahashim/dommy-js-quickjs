# frozen_string_literal: true

require "test_helper"
require_relative "../../support/wpt_conformance"

# Real WPT files for the WICG Observable proposal, run through WptRunner. The
# reactive primitive is implemented in JS (dommy's observable_runtime.js:
# Observable / Subscriber / EventTarget.prototype.when), so these files are what
# says whether that implementation is the spec's — and the baseline that a
# refactor of it has to keep.
#
# The expected failures fall into five groups:
#
#   * Detached documents. Dommy has no document detachment, so every subtest
#     that subscribes inside one (the whole of each `.window.js` file below)
#     cannot be represented. Those files are listed at min_pass: 0 rather than
#     dropped, so the day detachment is modeled the gap is visible here.
#   * One producer per Observable across concurrent subscriptions: the
#     subscribe callback is re-run per subscriber, where the spec shares the
#     producer and tears it down after the LAST subscriber leaves.
#   * `from()` over an async iterable: the IteratorRecord#return() contract (a
#     non-object result, a throwing return) and the microtask in which a
#     next()-getter error propagates.
#   * inspect()'s abort handler: whether it runs when the source completed
#     before the consumer unsubscribed, and where its own throw is reported.
#   * The microtask in which forEach's visitor-callback rejection lands.
class Dommy::Js::TestWptObservableFiles < Minitest::Test
  include Dommy::Js::WptConformance

  wpt_files(
    "dom/observable/tentative/observable-catch.any.js" => { min_pass: 9, expected: [] },
    "dom/observable/tentative/observable-constructor.any.js" => { min_pass: 40, expected: [
      "Multiple subscriptions share the same producer and teardown runs only after last subscription abort",
      "New subscription after complete creates new producer",
      "Teardown runs after last unsubscribe regardless of unsubscription order",
      "Subscriber iterates over a snapshot of its internal observers",
    ] },
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
    "dom/observable/tentative/observable-from.any.js" => { min_pass: 33, expected: [
      "from(): Asynchronous iterable multiple in-flight subscriptions",
      "from(): Sync iterable multiple in-flight subscriptions",
      "from(): Errors thrown in async iterator's next() GETTER are propagated in a microtask",
      "from(): Errors thrown in async iterator's next() are propagated in a microtask",
      "from(): Aborting async iterable midway through iteration both stops iteration and invokes `IteratorRecord#return()",
      "from(): Sync iterable: `Iterator#return()` must return an Object, or an error is thrown",
      "from(): Async iterable: `Iterator#return()` must return an Object, or a Promise rejects asynchronously",
      "from(): Asynchronous iterable conversion, with synchronous iterable fallback",
      "from(): Sync iterable: error thrown from IteratorRecord#return() can be synchronously caught",
      "from(): Async iterable: error thrown from IteratorRecord#return() is wrapped in rejected Promise",
      "from(): Subscribing to an iterable Observable with an aborted signal does not call next()",
      "from(): When iterable conversion aborts the subscription, next() is never called",
      "from(): Aborting an async iterable subscription stops subsequent next() calls, but old next() Promise reactions are web-observable",
      "from(): Abort after complete does NOT call IteratorRecord#return()",
      "No error is reported when aborting a subscription to a sync iterator that has no `return()` implementation",
    ] },
    "dom/observable/tentative/observable-inspect.any.js" => { min_pass: 10, expected: [
      "inspect(): Throwing an error in the observer error handler in inspect() is caught and sent to the error callback of the result observable",
      "inspect(): Inspector abort() handler is not called if the source completes before the result is unsubscribed from",
      "inspect(): Errors thrown from inspect()'s abort() handler are caught and reported to the global, because the subscription is already closed by the time the handler runs",
    ] },
    "dom/observable/tentative/observable-last.any.js" => { min_pass: 5, expected: [] },
    "dom/observable/tentative/observable-map.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-map.window.js" => { min_pass: 0, expected: [
      "map()'s internal observer's next steps do not crash in a detached document",
    ] },
    "dom/observable/tentative/observable-reduce.any.js" => { min_pass: 8, expected: [] },
    "dom/observable/tentative/observable-some.any.js" => { min_pass: 7, expected: [] },
    "dom/observable/tentative/observable-switchMap.any.js" => { min_pass: 6, expected: [] },
    "dom/observable/tentative/observable-take.any.js" => { min_pass: 5, expected: [
      "take(): No crash when take(1) unsubscribes from its source when next() is called, and the Subscriber iterates over the rest of the Observables",
    ] },
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
