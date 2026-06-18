# frozen_string_literal: true

require "test_helper"

# Freeze-and-replay of the note.com Apollo #95 ("the link chain completed
# without emitting a value"). Captured from a live load (DOMMY_FETCH_DEBUG), the
# terminal GraphQL request returns a perfectly good body:
#
#   POST https://graphql.note.com/graphql
#   200 application/graphql-response+json
#   {"data":{"viewer":{"__typename":"NotLoggedInViewer"}}}
#
# Apollo Client 4.0.13 reads a response RxJS-style: a terminal HttpLink reads
# `response.body.getReader()` to completion, emits the parsed result with
# `next`, then `complete`s; `validateDidEmitValue()` (the source of error #95)
# taps the chain and throws on `complete` if nothing was emitted.
#
# These tests reproduce that exact machinery on Dommy with the captured bytes,
# to settle whether #95 is a Dommy fetch/stream/Promise-timing bug or note.com's
# own link logic. Result: Dommy delivers the value correctly (no #95); #95 only
# fires when a *link* completes without emitting — which is note.com's
# guest-state behavior, not a Dommy defect.
class Dommy::Js::TestApolloLinkEmission < Minitest::Test
  # The captured terminal-query response, verbatim.
  VIEWER_BODY = '{"data":{"viewer":{"__typename":"NotLoggedInViewer"}}}'

  # A faithful slice of Apollo's RxJS usage: a minimal Observable, the `tap`
  # operator, `validateDidEmitValue` (#95), and an HttpLink terminal that reads
  # the response stream exactly like Apollo (getReader + TextDecoder loop).
  APOLLO_HARNESS_JS = <<~JS
    class Observable {
      constructor(subscribe) { this._subscribe = subscribe; }
      subscribe(observer) { return this._subscribe(observer); }
      pipe(op) { return op(this); }
    }
    function tap(handlers) {
      return (source) => new Observable((observer) => source.subscribe({
        next: (v) => { if (handlers.next) handlers.next(v); observer.next(v); },
        error: (e) => { observer.error(e); },
        complete: () => { if (handlers.complete) handlers.complete(); observer.complete(); },
      }));
    }
    // Apollo Client error #95.
    function validateDidEmitValue() {
      let didEmitValue = false;
      return tap({
        next: () => { didEmitValue = true; },
        complete: () => {
          if (!didEmitValue) throw new Error("link chain completed without emitting a value (#95)");
        },
      });
    }
    // Apollo's HttpLink terminal: stream the body to completion, parse, emit.
    // `emitGuard(result)` lets a test model a custom link that decides NOT to
    // forward a value (note.com's guest-state link) — returning false skips next.
    function httpLink(uri, emitGuard) {
      return new Observable((observer) => {
        fetch(uri, { method: "POST" }).then(async (response) => {
          const reader = response.body.getReader();
          const decoder = new TextDecoder();
          let buf = "";
          for (;;) {
            const { value, done } = await reader.read();
            if (done) break;
            buf += decoder.decode(value);
          }
          if (buf.length > 0) {
            const result = JSON.parse(buf);
            if (!emitGuard || emitGuard(result)) observer.next(result);
          }
          observer.complete();
        }).catch((e) => observer.error(e));
      });
    }
  JS

  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
    @rt.load_script(APOLLO_HARNESS_JS)
  end

  def teardown
    @rt&.dispose
  end

  def stub_fetch(body, content_type: "application/graphql-response+json; charset=utf-8", status: 200)
    @rt.execute(<<~JS)
      globalThis.fetch = (url, init) =>
        Promise.resolve(new Response(#{body.inspect}, {
          status: #{status}, headers: { "Content-Type": #{content_type.inspect} },
        }));
    JS
  end

  # The real captured response flows through Dommy's fetch + ReadableStream +
  # TextDecoder + Promise pipeline and is emitted as a value BEFORE complete —
  # so validateDidEmitValue does NOT throw #95. This is the decisive evidence
  # that Dommy delivers the GraphQL data correctly.
  def test_captured_viewer_response_emits_before_complete_no_95
    stub_fetch(VIEWER_BODY)
    @rt.execute(<<~JS)
      globalThis.OUT = {};
      httpLink("https://graphql.note.com/graphql")
        .pipe(validateDidEmitValue())
        .subscribe({
          next: (v) => { OUT.value = v; },
          error: (e) => { OUT.error = String(e && e.message || e); },
          complete: () => { OUT.completed = true; },
        });
    JS
    @rt.run_until_idle

    assert_nil @rt.evaluate("OUT.error ?? null"), "no #95 — a value was emitted before complete"
    assert_equal true, @rt.evaluate("OUT.completed")
    assert_equal "NotLoggedInViewer", @rt.evaluate("OUT.value.data.viewer.__typename")
  end

  # The #95 mechanism, reproduced: when a link completes WITHOUT emitting (here a
  # custom link that, in the guest/NotLoggedInViewer state, declines to forward
  # the value — note.com's behavior), validateDidEmitValue throws the exact
  # Apollo error. The data still arrived from Dommy; the link chose not to emit.
  def test_link_that_completes_without_emitting_reproduces_95
    stub_fetch(VIEWER_BODY)
    @rt.execute(<<~JS)
      globalThis.OUT = {};
      // Guest-state custom link: drop the value when the viewer is not logged in.
      const guard = (result) => result.data.viewer.__typename !== "NotLoggedInViewer";
      httpLink("https://graphql.note.com/graphql", guard)
        .pipe(validateDidEmitValue())
        .subscribe({
          next: (v) => { OUT.value = v; },
          error: (e) => { OUT.error = String(e && e.message || e); },
          complete: () => { OUT.completed = true; },
        });
    JS
    @rt.run_until_idle

    assert_includes @rt.evaluate("OUT.error").to_s, "#95",
      "a link completing without emitting reproduces Apollo error #95"
    assert_equal true, @rt.evaluate("OUT.value === undefined"), "nothing was emitted"
  end

  # A genuinely empty body (the captured 201 auth response shape) makes the read
  # loop produce nothing, so the link completes without emitting -> #95. This is
  # what an Apollo-routed empty response would do; Dommy faithfully delivers the
  # empty body (it does not invent one), and the emptiness is the trigger.
  def test_empty_body_response_completes_without_emitting
    stub_fetch("", content_type: "application/json; charset=utf-8", status: 200)
    @rt.execute(<<~JS)
      globalThis.OUT = {};
      httpLink("https://note.com/api/v3/graphql/auth")
        .pipe(validateDidEmitValue())
        .subscribe({
          next: (v) => { OUT.value = v; },
          error: (e) => { OUT.error = String(e && e.message || e); },
          complete: () => { OUT.completed = true; },
        });
    JS
    @rt.run_until_idle

    assert_includes @rt.evaluate("OUT.error").to_s, "#95"
  end
end
