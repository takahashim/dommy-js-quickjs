# Changelog

## 0.9.0 — 2026-06-22

The first substantial release since `0.1.0`. The version jumps to `0.9.0` to
line up with the rest of the Dommy monorepo (`dommy`, `dommy-rack`,
`capybara-dommy`). The headline change is architectural: the engine-agnostic
host layer and bridge now live in `dommy` core, leaving this gem as the QuickJS
backend that plugs into it. On top of that foundation sits real ESM and
JavaScript-framework support, an event-loop-aware runtime, and a large WHATWG /
WPT conformance pass.

Requires `dommy >= 0.9.0` and `quickjs ~> 0.18.0`.

### Added

#### Browser & page lifecycle
- `Dommy::Browser`, a lightweight test browser that boots a page, runs its
  scripts through a shared `ScriptBoot`, and exposes interaction verbs with a
  conservative `settle` step
- `Browser.open` settles after boot by default (opt out / tune with the
  `settle:` option)
- QuickJS is wired into Dommy page loads
- `SessionRuntime`, a JS host for the dommy-rack `Session`

#### ES Modules
- Full ESM support: `importmap`, the module loader, and `type=module` boot
- Inline modules' `import.meta.url` is pinned to the clean page URL
- External `<script src>` inserted into the DOM defers correctly rather than
  running synchronously during append

#### JavaScript frameworks
- Host and conformance coverage for **Stimulus** (with a ported QUnit suite),
  **React 18** (JSX, SSR, hydration), and **Vue 3** (global-scope script loading
  with tolerant handles)
- Integration suites for **Alpine**, **htmx**, **Solid**, and **Lit**

#### Event loop, timers & promises
- `evaluate` / `await` are event-loop-aware and settle task-resolved results
- The scheduler's microtask-checkpoint hook is wired up so host-side microtasks
  interleave with JS promises in FIFO order
- A throwing JS timer callback is isolated so it can no longer crash the host; a
  runaway (force-killed) callback is recorded rather than fatal, and a throwing
  callback is traced back to its scheduling site
- Ported the official **Promises/A+** suite against the host `PromiseValue`

#### Engine surface
- Polyfilled `Intl` and stubbed `WebAssembly` (the engine ships neither)
- More bare browser globals (`Image`, `Audio`, `Option`, `console`, `Object`, …)
  are aliased onto the global scope as the native globals
- The per-eval timeout is configurable via `DOMMY_JS_TIMEOUT_MSEC`
- Bridge crossing counts are exposed; opaque unhandled rejections are enriched

#### WPT / WHATWG conformance
- A resource-driven WPT runner plus a large vendored corpus: DOM nodes /
  traversal / ranges / collections, URL & URLSearchParams, Encoding, Selectors,
  CSS (syntax, variables, color, CSSOM), WAI-ARIA roles, and accessible-name
  (accname). The heavy thousands-of-subtests files are gated behind `WPT_HEAVY`.

### Changed

- **Pluggable runtime (breaking):** the engine-agnostic bridge and host layer
  (`Browser` + the Js port) moved into `dommy` core; the JS runtime is now
  pluggable and `Browser` is decoupled from QuickJS. This gem registers QuickJS
  as a backend. Bridge wire-protocol tags are centralized and `JSValue` unified.
- **Bridge contract (breaking):** defensive `Dommy::Bridge` guards were dropped
  in favor of requiring the backend contract; `dommy >= 0.9.0` is now required.
- Proxy identity and expando lifetime are preserved across crossings so reactive
  frameworks observe stable object identity; a `NodeList` crosses as a `NodeList`
  (not a plain array); `DOMException` subclasses cross as the single
  `DOMException` interface (`constructor === DOMException`).
- Callback exceptions propagate across the bridge; `NodeFilter` objects cross as
  live references.

### Fixed

- Survive a VM out-of-memory instead of crashing the browser
- Work around a QuickJS `for-of`-with-`yield`-in-iterable codegen bug
- Report a present-but-undefined IDL attribute via the `in` operator
- Scrub lone surrogates in dehydrated object keys

### Performance

- Skip the per-crossing Ruby `Timeout` (≈40% faster DOM crossings)
- Bytecode-cache the host runtime and external scripts

## 0.1.0

initial release.
