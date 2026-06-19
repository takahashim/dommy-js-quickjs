# frozen_string_literal: true

require "test_helper"

# Promises/A+ resolution-procedure conformance for Dommy's host PromiseValue
# (the promise returned by fetch / XHR / the body readers), focused on its
# interop with JS thenables — the area that had no oracle and let the HttpLink
# #95 reorder slip in.
#
# The official `promises-aplus-tests` suite drives a JS adapter that constructs
# the implementation's promises; it can't run against a Ruby-backed promise. So
# these pin the spec's §2.3 "Promise Resolution Procedure" invariants directly:
# when a `.then` callback returns a thenable (a native Promise, or any object
# with a callable `then`), the promise must ADOPT it — take its eventual state
# and value, after it settles — rather than fulfilling with it as an opaque
# value. A host PromiseValue is obtained from `fetch` (the realistic source).
class Dommy::Js::TestPromiseAplus < Minitest::Test
  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
    @win.__js_set__("__fetchy_stub__",
      { "https://g/q" => { "status" => 200, "body" => "seed", "contentType" => "text/plain" } })
  end

  def teardown
    @rt&.dispose
  end

  # Evaluate `body` (which sets globalThis.OUT) after driving the event loop.
  def out(body)
    @rt.execute("globalThis.OUT = undefined;\n#{body}")
    @rt.run_until_idle
    @rt.evaluate("globalThis.OUT")
  end

  # §2.3.2 — a host promise's `.then` adopts another host promise (the chain
  # waits and takes its value). (Host PromiseValue from fetch().then(...).)
  def test_adopts_a_host_promise_and_takes_its_value
    assert_equal "inner-value", out(<<~JS)
      fetch("https://g/q")
        .then(() => fetch("https://g/q").then(() => "inner-value"))
        .then((v) => { globalThis.OUT = v; });
    JS
  end

  # §2.3.3 — a returned NATIVE engine Promise is adopted; its resolved value
  # propagates downstream (not the promise object itself).
  def test_adopts_a_native_promise_and_propagates_its_value
    assert_equal 42, out(<<~JS)
      fetch("https://g/q")
        .then(() => Promise.resolve(42))
        .then((v) => { globalThis.OUT = v; });
    JS
  end

  # §2.3.3 — a returned native Promise that REJECTS routes to catch with its
  # reason (the rejection is adopted, not swallowed).
  def test_adopts_a_rejecting_native_promise
    assert_equal "boom", out(<<~JS)
      fetch("https://g/q")
        .then(() => Promise.reject(new Error("boom")))
        .then(() => { globalThis.OUT = "no-reject"; })
        .catch((e) => { globalThis.OUT = e.message; });
    JS
  end

  # §2.3.3.3 — a returned plain THENABLE (an object with a callable `then`, not a
  # Promise) is adopted: `then` is called and its resolve value propagates.
  def test_adopts_a_plain_thenable_object
    assert_equal "thenable-value", out(<<~JS)
      fetch("https://g/q")
        .then(() => ({ then: (resolve) => { resolve("thenable-value"); } }))
        .then((v) => { globalThis.OUT = v; });
    JS
  end

  # §2.3.3.3.4 — if a thenable's `then` THROWS, the promise rejects with the
  # thrown value.
  def test_thenable_whose_then_throws_rejects
    assert_equal "then-threw", out(<<~JS)
      fetch("https://g/q")
        .then(() => ({ then: () => { throw new Error("then-threw"); } }))
        .then(() => { globalThis.OUT = "no-reject"; })
        .catch((e) => { globalThis.OUT = e.message; });
    JS
  end

  # §2.3.3.3.3 — only the FIRST settle of a thenable counts; later calls are
  # ignored.
  def test_thenable_settles_only_once
    assert_equal "first", out(<<~JS)
      fetch("https://g/q")
        .then(() => ({ then: (resolve) => { resolve("first"); resolve("second"); } }))
        .then((v) => { globalThis.OUT = v; });
    JS
  end

  # §2.3.4 — a returned NON-thenable (a plain value) fulfills directly, with no
  # adoption.
  def test_non_thenable_fulfills_directly
    assert_equal({ "ok" => true }, out(<<~JS)
      fetch("https://g/q")
        .then(() => ({ ok: true }))
        .then((v) => { globalThis.OUT = v; });
    JS
    )
  end

  # The adoption WAITS: a slow thenable (resolved on a later task) defers
  # downstream until it settles — the ordering invariant behind the HttpLink fix.
  def test_adoption_waits_for_an_async_thenable
    assert_equal "inner,after", out(<<~JS)
      globalThis.LOG = [];
      fetch("https://g/q")
        .then(() => new Promise((resolve) => setTimeout(() => { LOG.push("inner"); resolve(); }, 5)))
        .then(() => { LOG.push("after"); globalThis.OUT = LOG.join(","); });
    JS
  end
end
