# frozen_string_literal: true

require "test_helper"

# Exercises the `new Response(body, init)` constructor and the
# `Runtime#run_until_idle` deterministic drain — the two pieces Lilac's
# `dommy-js-quickjs` integration depends on. The fetch stub installed here is a
# verbatim shape of Lilac's `install_fetch_stub`
# (lilac/runtime/mruby-lilac-async/wasm_spec/test_fetchy.rb): a `globalThis.fetch`
# that resolves `new Response(...)`, with a delayed + AbortSignal-driven path.
class Dommy::Js::TestFetchResponse < Minitest::Test
  def setup
    @win = Dommy.parse("<html><body></body></html>")
    @rt = Dommy::Js::Quickjs::Runtime.new
    @rt.install_window(@win)
    @rt.install_browser_globals
  end

  def teardown
    @rt&.dispose
  end

  # `new Response(...)` is constructable from JS and its full read surface works.
  def test_response_constructor_read_surface
    result = @rt.evaluate(<<~JS)
      (async () => {
        const r = new Response("hello\\nworld", {
          status: 201, statusText: "Created", headers: { "X-A": "1" },
        });
        const body = await r.text();
        return [r.status, r.statusText, r.ok, r.url, r.redirected, body,
                r.headers.get("X-A"), r instanceof Response];
      })()
    JS
    assert_equal [201, "Created", true, "", false, "hello\nworld", "1", true], result
  end

  def test_response_defaults
    result = @rt.evaluate("(() => { const r = new Response(); return [r.status, r.ok, r.statusText]; })()")
    assert_equal [200, true, ""], result
  end

  def test_response_out_of_range_status_throws_range_error
    name = @rt.evaluate(<<~JS)
      (() => {
        try { new Response("x", { status: 42 }); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "RangeError", name
  end

  # WHATWG: a null-body status (204/205/304) with a body is a TypeError.
  def test_null_body_status_with_body_throws_type_error
    name = @rt.evaluate(<<~JS)
      (() => {
        try { new Response("body", { status: 204 }); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "TypeError", name
  end

  # response.arrayBuffer() resolves to a typed-array byte buffer (a BufferSource
  # with a real byteLength), not a plain JS array. The bridge marshals all host
  # byte buffers to Uint8Array uniformly (as TextEncoder.encode / Blob do), so
  # the value is a Uint8Array view rather than a bare ArrayBuffer.
  def test_array_buffer_is_a_typed_array_buffer
    result = @rt.evaluate(<<~JS)
      (async () => {
        const buf = await new Response("AB").arrayBuffer();
        return [ArrayBuffer.isView(buf), buf.byteLength, Array.from(new Uint8Array(buf.buffer))];
      })()
    JS
    assert_equal [true, 2, [65, 66]], result
  end

  # Static Response.json(data, init).
  def test_static_response_json
    result = @rt.evaluate(<<~JS)
      (async () => {
        const r = Response.json({ a: 1 }, { status: 201 });
        return [r.status, r.headers.get("Content-Type"), await r.text()];
      })()
    JS
    assert_equal [201, "application/json", '{"a":1}'], result
  end

  # Static Response.redirect(url, status) — Location header + redirect status.
  def test_static_response_redirect
    result = @rt.evaluate(<<~JS)
      (() => {
        const r = Response.redirect("https://example.test/x", 301);
        return [r.status, r.headers.get("Location")];
      })()
    JS
    assert_equal [301, "https://example.test/x"], result
  end

  def test_static_response_redirect_invalid_status_throws_range_error
    name = @rt.evaluate(<<~JS)
      (() => {
        try { Response.redirect("/y", 200); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "RangeError", name
  end

  # Static Response.error() — a network-error response (status 0, not ok).
  def test_static_response_error
    assert_equal [0, false], @rt.evaluate("(() => { const r = Response.error(); return [r.status, r.ok]; })()")
  end

  # WHATWG Headers iterate sorted, lowercased.
  def test_headers_iterate_sorted_lowercased
    result = @rt.evaluate(<<~JS)
      (() => {
        const r = new Response("x", { headers: { "X-Foo": "1", "Accept": "2" } });
        return Array.from(r.headers.entries());
      })()
    JS
    # "accept" sorts before "content-type" (added for the body) before "x-foo".
    assert_equal [["accept", "2"], ["content-type", "text/plain;charset=UTF-8"], ["x-foo", "1"]], result
  end

  # Lilac's stub shape: a globalThis.fetch resolving `new Response(...)`.
  def test_lilac_fetch_stub_resolved_response
    @rt.execute(<<~JS)
      globalThis.fetch = (url, init) =>
        Promise.resolve(new Response('[{"id":1}]', {
          status: 200, headers: { "Content-Type": "application/json" },
        }));
      globalThis.S = {};
      fetch("/api").then(async (r) => {
        S.status = r.status;
        S.ct = r.headers.get("Content-Type");
        S.body = await r.text();
      });
    JS
    @rt.run_until_idle
    assert_equal [200, "application/json", '[{"id":1}]'], @rt.evaluate("[S.status, S.ct, S.body]")
  end

  # The delayed-response path settles in a single run_until_idle (a setTimeout
  # inside the fetch promise + a chained await all drain deterministically).
  def test_delayed_response_settles_via_run_until_idle
    @rt.execute(<<~JS)
      globalThis.S = {};
      globalThis.fetch = (url, init) =>
        new Promise((resolve) => {
          setTimeout(() => resolve(new Response("late", { status: 200 })), 50);
        });
      fetch("/slow").then(async (r) => { S.status = r.status; S.body = await r.text(); });
    JS
    @rt.run_until_idle
    assert_equal [200, "late"], @rt.evaluate("[S.status, S.body]")
  end

  # The AbortSignal-driven reject path: aborting before the timer fires rejects
  # with an AbortError, mirroring Lilac's stub.
  def test_abort_rejects_with_abort_error
    @rt.execute(<<~JS)
      globalThis.S = {};
      const ctrl = new AbortController();
      globalThis.fetch = (url, init) =>
        new Promise((resolve, reject) => {
          const t = setTimeout(() => resolve(new Response("late", { status: 200 })), 50);
          init.signal.addEventListener("abort", () => {
            clearTimeout(t);
            const e = new Error("aborted"); e.name = "AbortError"; reject(e);
          });
        });
      fetch("/slow", { signal: ctrl.signal })
        .then(() => { S.outcome = "resolved"; })
        .catch((e) => { S.outcome = e.name; });
      ctrl.abort();
    JS
    @rt.run_until_idle
    assert_equal "AbortError", @rt.evaluate("S.outcome")
  end
end
