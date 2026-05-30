# Dommy-side bridge gaps (batch later)

Things discovered while bringing up real frameworks (Turbo) and the WPT-JS
harness that are best fixed on the **Dommy** side. (dommy-js-quickjs-side gaps
are tracked in the code / bridge-redesign.md.)

Last reviewed: 2026-05-30 (after Dommy `67a3d15`).

## Resolved

- **JS-callable method-name coverage + drift** — Dommy `67a3d15` replaced the
  per-class `JS_METHOD_NAMES` + `__js_method_names__` boilerplate with a
  `js_methods %w[...]` macro (`Bridge::Methods` mixin; subclass composition is
  automatic), declared it on the ~40 classes that lacked it, and added an
  AST-invariant test asserting the declared names equal each `__js_call__`'s
  `when` arms (two-way drift is now a CI failure). The bridge still reads
  `__js_method_names__`, so this is transparent here (109 tests green against the
  refactor). Function-style/internal adapters (`Fetch`, `DatasetMap`, `Bridge::*`)
  are allowlisted — they don't expose named methods, which is correct.

- **Top-level window self-references** — Dommy `Window#__js_get__` now returns the
  window itself for `window` / `self` / `parent` / `top` / `frames`, so
  `window === window.parent` and frame-walking loops (e.g. testharness.js's
  `while (w != w.parent)`) terminate. The bridge also sets `globalThis.parent` /
  `top = globalThis` in `install_browser_globals` for the bare/`self` path
  (`self` is the VM global, distinct from the window proxy).

## Remaining

### 1. Static / class methods on interface constructors  (medium; WPT-URL relevant)
`URL.createObjectURL` / `revokeObjectURL` / `parse` / `canParse`, `Response.json`
(static), etc. are **not reachable**:
- bare `URL` is the seeded interface constructor (a plain fn from `protoForChain`)
  → no statics.
- `window.URL` is Dommy's `Bridge::Constructor` (it dispatches class methods via
  `define_class_method` + `__js_call__`), but `Bridge::Constructor` is allowlisted
  (no `js_methods`), so its statics aren't exposed as callable either.

Plan (bridge + Dommy): have `Bridge::Constructor` expose its class-method names
(e.g. a small ABI accessor), and have the bridge attach delegating functions for
them onto the seeded bare global when that interface is constructable. Edge for
frameworks (Turbo didn't need it); matters for WPT `url/` conformance.

### 2. Incomplete polyfills surface ad hoc  (ongoing)
Some polyfills are partial and only reveal gaps when exercised — e.g. `Headers`
was read-only (no `append`/`set`/`delete`) until Turbo hit it (now fixed). Expect
similar as more framework/WPT paths run; fix on discovery. The **WPT-JS harness**
is the way to enumerate these systematically (run a WPT `.js`/`.html` test,
harvest per-subtest pass/fail via `add_completion_callback`; failures point at the
missing Dommy surface). Run it over `dom/`, `domparsing/`, `url/`, … for a
concrete backlog.
