# frozen_string_literal: true

require "test_helper"

# The engine stringifies a non-Error promise rejection reason to "[object
# Object]" before Ruby sees it, hiding the real cause (e.g. a React/GraphQL error
# object). With DOMMY_JS_DEBUG_REJECTIONS the runtime installs a JS-side recorder
# that captures the reason's rich detail at reject time and backfills the
# detail-less report — making an opaque hydration failure diagnosable.
class Dommy::Js::TestRejectionDetail < Minitest::Test
  def teardown
    @rt&.dispose
  end

  def run_with(env)
    ENV["DOMMY_JS_DEBUG_REJECTIONS"] = env
    win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    errors = []
    @rt.on_unhandled_rejection { |e| errors << e.message.to_s }
    @rt.install_window(win)
    @rt.install_browser_globals
    @rt.execute("Promise.reject({ code: 'BOOM', message: 'a real detail', extensions: { kind: 'X' } });")
    @rt.run_until_idle
    errors
  ensure
    ENV.delete("DOMMY_JS_DEBUG_REJECTIONS")
  end

  def test_rich_detail_is_surfaced_when_enabled
    errors = run_with("1")

    assert errors.any? { |m| m.include?("BOOM") && m.include?("a real detail") && m.include?("extensions") },
      "expected the rejection's real content, got: #{errors.inspect}"
  end

  def test_opaque_by_default
    errors = run_with("")

    assert_includes errors, "[object Object]", "default: no tracker, the engine's opaque report"
  end
end
