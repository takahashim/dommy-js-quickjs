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

  # response.arrayBuffer() resolves to a real (bare) ArrayBuffer — its spec
  # return type — not a Uint8Array view or a plain JS array.
  def test_array_buffer_is_a_real_array_buffer
    result = @rt.evaluate(<<~JS)
      (async () => {
        const buf = await new Response("AB").arrayBuffer();
        return [buf instanceof ArrayBuffer, ArrayBuffer.isView(buf),
                buf.byteLength, Array.from(new Uint8Array(buf))];
      })()
    JS
    assert_equal [true, false, 2, [65, 66]], result
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

  # WHATWG: an invalid header name / value throws a TypeError from JS.
  def test_invalid_header_name_throws_type_error
    name = @rt.evaluate(<<~JS)
      (() => {
        try { new Headers({ "Inv@lid": "x" }); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "TypeError", name
  end

  def test_invalid_header_value_throws_type_error
    name = @rt.evaluate(<<~JS)
      (() => {
        const h = new Headers();
        try { h.set("X", "a\\r\\nInjected: 1"); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "TypeError", name
  end

  # WHATWG: Set-Cookie is not combined; getSetCookie splits it.
  def test_set_cookie_split
    result = @rt.evaluate(<<~JS)
      (() => {
        const h = new Headers([["Set-Cookie", "a=1"], ["Set-Cookie", "b=2"]]);
        return [h.getSetCookie(), h.get("set-cookie")];
      })()
    JS
    assert_equal [["a=1", "b=2"], "a=1, b=2"], result
  end

  # WHATWG: Response.redirect parses the URL; an invalid one throws a TypeError.
  def test_redirect_invalid_url_throws_type_error
    name = @rt.evaluate(<<~JS)
      (() => {
        try { Response.redirect("http://", 302); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "TypeError", name
  end

  # WHATWG: Response.error()/redirect() headers are immutable — mutation throws.
  def test_error_headers_are_immutable
    name = @rt.evaluate(<<~JS)
      (() => {
        try { Response.error().headers.set("X-A", "1"); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "TypeError", name
  end

  # WHATWG: Response.json(undefined) / Response.json() is not serializable.
  def test_json_undefined_throws_type_error
    results = @rt.evaluate(<<~JS)
      (() => {
        const out = [];
        for (const data of [undefined]) {
          try { Response.json(data); out.push("no-throw"); }
          catch (e) { out.push(e.constructor.name); }
        }
        try { Response.json(); out.push("no-throw"); }
        catch (e) { out.push(e.constructor.name); }
        return out;
      })()
    JS
    assert_equal ["TypeError", "TypeError"], results
  end

  # JS null is serializable -> body "null".
  def test_json_null_serializes
    assert_equal "null", @rt.evaluate('(async () => await Response.json(null).text())()')
  end

  # WHATWG: an invalid statusText (control chars) throws a TypeError.
  def test_invalid_status_text_throws_type_error
    name = @rt.evaluate(<<~JS)
      (() => {
        try { new Response("x", { statusText: "bad\\r\\n" }); return "no-throw"; }
        catch (e) { return e.constructor.name; }
      })()
    JS
    assert_equal "TypeError", name
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

  # WHATWG: response.body is a ReadableStream whose reader yields the bytes.
  def test_body_is_readable_stream
    result = @rt.evaluate(<<~JS)
      (async () => {
        const r = new Response("hello");
        const isStream = r.body instanceof ReadableStream;
        const identity = r.body === r.body; // getting .body does not consume
        const reader = r.body.getReader();
        const { value, done } = await reader.read();
        const text = new TextDecoder().decode(value);
        const next = await reader.read();
        return [isStream, identity, text, done, next.done];
      })()
    JS
    assert_equal [true, true, "hello", false, true], result
  end

  # A null-body response (204) has a null body.
  def test_null_body_is_null
    assert_equal true, @rt.evaluate("new Response(null, { status: 204 }).body === null")
  end

  # WHATWG: bodyUsed tracks consumption; a second consume rejects.
  def test_body_used_and_double_consume_rejects
    result = @rt.evaluate(<<~JS)
      (async () => {
        const r = new Response("x");
        const before = r.bodyUsed;
        await r.text();
        const after = r.bodyUsed;
        let secondErr = "no-throw";
        try { await r.text(); } catch (e) { secondErr = e.name; }
        return [before, after, secondErr];
      })()
    JS
    assert_equal [false, true, "TypeError"], result
  end

  # response.type — "default" for constructed, "error" for Response.error().
  def test_response_type
    assert_equal ["default", "error"],
      @rt.evaluate('[new Response("x").type, Response.error().type]')
  end

  # WHATWG "extract a body": a Blob body uses its bytes + MIME type; a
  # URLSearchParams body serializes to urlencoded with the matching type.
  def test_non_string_body_extraction
    result = @rt.evaluate(<<~JS)
      (async () => {
        const blobResp = new Response(new Blob(["hi"], { type: "text/markdown" }));
        const uspResp = new Response(new URLSearchParams({ a: "1", b: "2" }));
        return [
          await blobResp.text(), blobResp.headers.get("Content-Type"),
          await uspResp.text(), uspResp.headers.get("Content-Type"),
        ];
      })()
    JS
    assert_equal ["hi", "text/markdown", "a=1&b=2",
                  "application/x-www-form-urlencoded;charset=UTF-8"], result
  end
end
