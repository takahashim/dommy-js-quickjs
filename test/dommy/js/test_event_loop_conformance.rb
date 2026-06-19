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

  # A fetch response is delivered by a *task* (the networking task source), not
  # inline during the fetch() call. So the synchronous script's own microtasks
  # (queueMicrotask / a settled Promise's reaction) must all run — at the
  # microtask checkpoint after the current task — BEFORE fetch's reaction, which
  # waits for a later task. Resolving fetch inline (as Dommy's synchronous path
  # did) collapses this, running fetch's reaction among the script's microtasks
  # — exactly the event-loop collapse that breaks Apollo/RxJS link chains (#95).
  def test_fetch_resolves_in_a_later_task_not_among_script_microtasks
    @win.__js_set__("__fetchy_stub__",
      { "https://g/q" => { "status" => 200, "body" => "ok", "contentType" => "text/plain" } })
    @rt.execute(<<~JS)
      globalThis.ORDER = [];
      fetch("https://g/q").then(() => { ORDER.push("fetch"); });
      queueMicrotask(() => { ORDER.push("microtask"); });
      Promise.resolve().then(() => { ORDER.push("promise"); });
    JS
    @rt.run_until_idle

    assert_equal "microtask,promise,fetch", order,
      "fetch resolves in a later task, after the script's microtask checkpoint"
  end

  # HTML timer initialization steps: a timer nested deeper than 5 with a sub-4ms
  # timeout is clamped to 4ms. Besides matching browsers, this is what keeps a
  # self-rescheduling setTimeout(0) from spinning forever at the same instant —
  # it advances into a future frame instead. Here: a chain of setTimeout(0) that
  # records the virtual time at each step must show the clock jump to >=4ms once
  # nesting passes 5 (steps 1..5 at t=0, step 6 onward clamped).
  def test_nested_setTimeout0_is_clamped_to_4ms_after_5_levels
    @rt.execute(<<~JS)
      globalThis.TIMES = [];
      function step() {
        TIMES.push(performance.now());
        if (TIMES.length < 8) setTimeout(step, 0);
      }
      setTimeout(step, 0);
    JS
    @rt.run_until_idle

    times = @rt.evaluate("globalThis.TIMES")
    assert_equal 8, times.length
    # The first several nested setTimeout(0) fire at the same instant; once past
    # the nesting threshold the clamp pushes each ~4ms later, so time advances.
    assert_equal 0, times.first, "the first timer fires at t=0"
    assert_operator times.last, :>=, 4, "deep nesting is clamped, so the clock advanced"
  end

  # WHATWG web-messaging: MessagePort.postMessage delivers its `message` event
  # from a TASK (the "post message" task source), not a microtask. So the
  # script's own microtasks (queueMicrotask, a settled Promise) all run first, at
  # the checkpoint after the current task, and the message arrives in a later
  # task. This is the mechanism React's scheduler relies on to yield as a
  # macrotask — delivering it as a microtask makes React never yield.
  def test_message_port_postmessage_is_a_task_not_a_microtask
    @rt.execute(<<~JS)
      globalThis.ORDER = [];
      const mc = new MessageChannel();
      mc.port2.onmessage = () => { ORDER.push("message"); };
      mc.port1.postMessage("x");
      queueMicrotask(() => { ORDER.push("microtask"); });
      Promise.resolve().then(() => { ORDER.push("promise"); });
    JS
    @rt.run_until_idle

    assert_equal "microtask,promise,message", order,
      "MessagePort.postMessage delivers via a task, after the microtask checkpoint"
  end
end
