# Promises/A+ official compliance suite (vendored)

`tests/` is the unmodified official [promises-aplus-tests][suite] case set
(the `lib/tests/` + `lib/tests/helpers/` of that package). It drives an
**adapter** — `{ deferred, resolved, rejected }` — against an implementation's
promises and checks the full [Promises/A+ §2][spec] resolution procedure
(~872 specs).

Here the adapter is backed by Dommy's host `PromiseValue` (the promise that
`fetch` / XHR / the stream readers return), so the suite verifies that a host
promise driven from JS is spec-conformant — the area that had no oracle and let
the Apollo HttpLink `#95` microtask reorder slip in.

- `harness.js` — shims the suite's Node dependencies inside the QuickJS realm
  (CommonJS `require`, `assert`, a minimal `sinon`, mocha's
  `describe`/`specify`/hooks), wires the adapter to `__rbHost.makeHostDeferred`,
  and exposes `globalThis.__aplus` for the Ruby driver to run each case while
  draining the scheduler between them.
- `../../dommy/js/test_promises_aplus_official.rb` — the Ruby driver.

The suite is upstream-licensed **WTFPL**; `harness.js` and the driver are part
of Dommy.

To refresh: `npm i promises-aplus-tests` and copy `lib/tests/` over `tests/`.

[suite]: https://github.com/promises-aplus/promises-tests
[spec]: https://promisesaplus.com/
