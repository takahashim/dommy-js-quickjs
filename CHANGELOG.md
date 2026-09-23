# Changelog

## Unreleased

### Added

- Rejections are handed to a JS hook (`promise_rejection_hook=`) when the engine has one, so the promise and the reason cross as the values the page threw rather than an exception the engine already converted. That is what makes `event.reason`, `event.promise` and `rejectionhandled` work at all. `on_unhandled_rejection` goes quiet while the hook is installed, since both would report the same rejection.
- `Runtime#rebuild_error` builds a real `Error` inside the realm from an exception QuickJS raised for a script's throw, so `event.error` reaches the page with the name, message and stack it threw instead of an object with no properties. The engine discards the JS value when it converts the throw, so the rebuilt error matches on everything observable except identity.

### Changed

- Requires `dommy >= 0.13.0` (was `>= 0.10.0`), the release carrying the JS error-report API this gem's suite drives (`Window#__internal_on_unhandled_error__`, `Browser#error_log`, `Dommy::JsError`).
- Requires `quickjs ~> 0.21.0` (was `~> 0.18.0`). Until both fixes are released upstream, the Gemfile pins [takahashim/quickjs.rb#feat/rejection-js-hook](https://github.com/takahashim/quickjs.rb/tree/feat/rejection-js-hook). It carries the JS rejection hook above, and sits on the checkpoint-timing fix ([hmsk/quickjs.rb#141](https://github.com/hmsk/quickjs.rb/pull/141)) that reports an unhandled rejection at the end of the microtask checkpoint as HTML requires, rather than the moment a promise rejects. Without the latter, `Promise.reject(x).catch(...)` and `try { await rejecting() } catch {}` are both misreported as unhandled — correct code that a strict host then fails a test on.
- `SourceGuard` is gone. It rewrote a `for...of` whose iterable contains a `yield` and retried, working around a QuickJS codegen bug ("stack underflow") that broke real SPA bundles. The QuickJS that 0.21 vendors compiles the construct, and the gemspec requires `~> 0.21.0`, so nothing could reach the retry — and nothing could test it either. Revert the removal if the bug ever comes back.
- The gem's per-crossing `Timeout.timeout` is skipped by prepending to `::Quickjs`'s singleton rather than redefining `_with_timeout` outright, so the original stays reachable and the patch is visible in `ancestors`.
- Every Backend entry point that runs something in the VM is guarded against a poisoned one, not just three of the six. After an out-of-memory an inline script quietly did nothing while an external (bytecode) script and `#evaluate` raised "VM is poisoned" from a different place each time; all of them now no-op, which is the "browsing never crashes" contract the guarded three already followed.
- `DOMMY_JS_MEMORY_LIMIT_MB` sets the VM's memory ceiling, as `DOMMY_JS_TIMEOUT_MSEC` does the per-eval timeout. Lowering it is how the out-of-memory path gets exercised deliberately.
- The realm's JavaScript (the Intl polyfill, the WebAssembly stub, the aliased browser globals, the mirrored built-ins, the timer instrumentation) moved out of Ruby heredocs into `.js` files under `lib/dommy/js/quickjs/js/`, installed by a new `BrowserEnvironment` through `Backend#run_bundle` — so each payload is compiled once per process rather than reparsed for every VM.
- `Runtime` delegates to `EventLoop` (the microtask queue and Dommy's scheduler as one loop, with the three drivers sharing a pump), `ErrorTranslator` (an engine exception as what the page should see) and `Config` (every `DOMMY_JS_*` variable). Its public surface is now the Runtime port plus what hosts call; `evaluate_settled`, `bump_dom_epoch` and the other internals are private.
- `Runtime#load_module` and `Backend#import_module` are gone, unused: an inline `<script type="module">` reaches the engine through `load_module_url`.
- `install_wasm_memory_shim` installs the same WebAssembly stub as `install_browser_globals` rather than a second, near-identical one.
- The vendored WPT tree is pinned to a single upstream revision (`test/fixtures/wpt/UPSTREAM_REVISION`) and refreshed with `script/vendor_wpt.sh`, rather than growing file by file from whatever upstream was that day. Refreshing to `2f7c700` moved 24 files; `url-constructor.any.js` is green again, since upstream now expects an undecodable A-label like `https://xn--/` to parse.

### Fixed

- A classic script whose completion value is a pending Promise — `window.p = new Promise(...)` as its last statement, the idiom for publishing one a later script awaits — no longer reaches the page as an uncaught error. The gem refuses to convert such a value, and the resulting host exception was reported at the window; a testharness page that saw it reported no results at all. `#load_script` and `#load_script_cached` now discard the completion value, which `#execute` already did by wrapping in an IIFE.
- `Runtime#rebuild_error` no longer copies a host exception's Ruby backtrace into the rebuilt Error's `stack`, which published this gem's file paths to any page that reads it. Engine frames are kept, everything else dropped, and a backtrace with no JS frames leaves the stack empty rather than naming a place the page did not fail.

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
