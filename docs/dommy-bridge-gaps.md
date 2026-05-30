# Dommy-side bridge gaps (batch later)

Things discovered while bringing up real frameworks (Turbo) and the WPT-JS
harness that are best fixed on the **Dommy** side. Recorded for a later batch;
not blocking current work. (dommy-js-quickjs-side gaps are tracked in the code /
bridge-redesign.md.)

Last reviewed: 2026-05-30.

## Status: the big gap is essentially closed

The class-level audit ("`__js_call__` present but `__js_method_names__` missing")
that started at ~40 classes is now down to **6**, all legitimate non-needs:

- `Bridge::Callback`, `Bridge::Constructor`, `Bridge::PromiseConstructor`,
  `Bridge::PromiseSettler` — bridge adapters dispatched specially (`__js_new__` /
  `__js_call__("call")`), not accessed as objects with named methods.
- `DatasetMap` — `el.dataset.foo` is property access (`__js_get__`/`__js_set__`);
  verified working. No methods to expose.
- `FetchFn` — invoked as `window.fetch(...)` (a Window method), not as an object.

So no further blanket `__js_method_names__` work is needed. The items below are
specific.

## Genuine items

### 1. Static / class methods on interface constructors  (medium)
`URL.createObjectURL` / `revokeObjectURL` / `parse` / `canParse`, `Response.json` /
`redirect` / `error`, etc. are **not reachable**:
- bare `URL` is the seeded interface constructor (a plain fn) → no statics.
- `window.URL` is Dommy's `Bridge::Constructor` (it has `define_class_method`) but
  exposes no `__js_method_names__`, so `window.URL.createObjectURL` isn't callable
  either.

Needs a decision on where statics live: either the bridge copies a constructor's
class methods onto the seeded global, or Dommy exposes them via the proxy. Matters
for WPT URL tests and Blob-URL workflows. (Turbo did not need these.)

### 2. Top-level window self-references  (low — worked around)
`window.parent` / `top` / `self` / `frames` return `nil`; per spec a top-level
window's `parent`/`top` are the window itself. testharness.js walks
`while (w != w.parent)` and dereferenced `undefined`.

Worked around bridge-side in `Runtime#install_browser_globals`
(`globalThis.parent = globalThis; globalThis.top = globalThis`). Dommy could
return `self` for these so non-harness consumers get correct behavior too.

### 3. Incomplete polyfills surface ad hoc  (ongoing)
Some polyfills are partial and only reveal gaps when exercised — e.g. `Headers`
was read-only (no `append`/`set`/`delete`) until Turbo hit it. Expect similar as
more framework/WPT paths run. Not a fixed list; fix on discovery.

## Enumeration tool

The **WPT-JS harness** (testharness.js + `BrowserHarness`, see
`test/dommy/js/` once landed) is the way to enumerate remaining DOM coverage gaps
systematically: run a WPT `.js`/`.html` test, harvest per-subtest pass/fail via
`add_completion_callback`, and the failures point at the missing Dommy surface.
Run it over `dom/`, `domparsing/`, `url/`, … to produce a concrete, prioritized
backlog (rather than guessing).

## Refactoring note (aligns with the in-progress Dommy refactor)
`__js_method_names__` lists are kept in sync with each `__js_call__` `when`-arm by
hand ("keep in sync with its when-arms" comments). A small shared helper
(e.g. `js_methods :a, :b` defining both the constant and the reader, or deriving
names) would remove that drift risk across the now-many bridge classes.
