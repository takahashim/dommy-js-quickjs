# frozen_string_literal: true

require "test_helper"

# WHATWG event-loop processing-model conformance.
#
# These tests pin the spec's *ordering* invariants (HTML §8.1.7.3 "Event loop
# processing model"), which Dommy had no oracle for — and which a real SPA's
# data layer (Apollo/RxJS) depends on. The central invariant is the **microtask
# checkpoint after every task**: run one task to completion, then drain the
# entire microtask queue, *before* the next task runs.
#
# The seed test mirrors WPT html/webappapis/timers/evil-spec-example.html, which
# encodes the example from the spec itself: a microtask queued by one task must
# run before the next task begins.
class Dommy::Js::TestEventLoopConformance < Minitest::Test
  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  # The order events were observed in, as a comma-joined string.
  def order = @rt.evaluate("globalThis.ORDER.join(',')")

  # WPT evil-spec-example: two setTimeout(0) tasks; the first queues a microtask.
  # Per the processing model a microtask checkpoint runs after each task, so the
  # microtask MUST run before the second task. Spec order: task1, microtask,
  # task2 — NOT task1, task2, microtask (which is what batching all due timers
  # then draining once produces).
  def test_microtask_checkpoint_runs_between_two_tasks
    @rt.execute(<<~JS)
      globalThis.ORDER = [];
      setTimeout(() => {
        ORDER.push("task1");
        Promise.resolve().then(() => { ORDER.push("microtask"); });
      }, 0);
      setTimeout(() => { ORDER.push("task2"); }, 0);
    JS
    @rt.run_until_idle

    assert_equal "task1,microtask,task2", order,
      "a microtask checkpoint must run after task1 and before task2 (HTML event loop §8.1.7.3)"
  end
end
