# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A quickjs that reports a promise rejection before a handler can attach (the
# released 0.21.0) would turn every `.catch` and `try { await … } catch` into
# an unhandled rejection, failing a strict host on correct code. On such an
# engine the Ruby rejection callback relays nothing; on a fixed one it relays
# as before. (With the JS rejection hook installed it is not used at all, so
# these runtimes stay without a window.)
class Dommy::Js::TestPrematureRejectionReports < Minitest::Test
  Backend = Dommy::Js::Quickjs::Backend
  Runtime = Dommy::Js::Quickjs::Runtime

  def reported_with(premature:)
    runtime = Runtime.new
    reported = []
    runtime.on_unhandled_rejection { |error| reported << error }
    Backend.stub(:premature_rejection_reports?, premature) do
      Runtime.stub(:warn_premature_rejection_reports, nil) do
        runtime.execute("Promise.reject(new Error('nobody handles this'))")
        runtime.drain_microtasks
      end
    end
    reported
  ensure
    runtime&.dispose
  end

  def test_an_engine_that_reports_on_time_is_relayed
    assert_equal(1, reported_with(premature: false).size)
  end

  def test_an_engine_that_reports_too_early_is_not
    assert_empty(reported_with(premature: true))
  end

  def test_the_probe_is_decided_once
    first = Backend.premature_rejection_reports?
    assert_includes([true, false], first)
    assert_same(first, Backend.premature_rejection_reports?)
  end
end
