# frozen_string_literal: true

require "test_helper"

# The quickjs gem wraps every host-function call (every JS->Ruby DOM crossing) in
# Timeout.timeout, which dominates the cost of a DOM-heavy SPA. The backend skips
# it for speed (see backend.rb). These pin the safety invariant: the
# JS-execution timeout — enforced by QuickJS's OWN C interrupt handler,
# independent of the Ruby wrapper — must still force-abort a runaway loop, so a
# page can't hang the host forever.
class Dommy::Js::TestCrossingFastPath < Minitest::Test
  Backend = Dommy::Js::Quickjs::Backend

  def test_runaway_js_is_still_aborted_at_the_eval_timeout
    skip "fast path disabled" unless ENV["DOMMY_JS_CROSSING_TIMEOUT"].to_s.empty?

    backend = Backend.new(timeout_msec: 300)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(::Quickjs::RuntimeError) do
      backend.eval("while (true) {}")
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 5, "the runaway loop was aborted promptly, not left to hang"
  end

  def test_a_host_crossing_still_works_through_the_fast_path
    skip "fast path disabled" unless ENV["DOMMY_JS_CROSSING_TIMEOUT"].to_s.empty?

    win = Dommy.parse("<html><body><p id='x'>hi</p></body></html>")
    rt = Dommy::Js::Quickjs::Runtime.new
    rt.install_window(win)
    rt.install_browser_globals
    rt.define_host_object("document", win.document)

    assert_equal "P", rt.evaluate("document.getElementById('x').tagName")
  ensure
    rt&.dispose
  end
end
