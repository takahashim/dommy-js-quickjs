# Dommy::Js::Quickjs

Run real JavaScript — including real frontend frameworks — against a
[Dommy](https://github.com/takahashim/dommy) DOM, without a browser.

JavaScript executes in an embedded QuickJS VM (via the
[`quickjs`](https://github.com/hmsk/quickjs.rb) gem). Dommy DOM nodes are bridged
to JS as objects whose property/method access routes into Dommy's
`__js_get__` / `__js_set__` / `__js_call__` / `__js_new__` ABI, so JS drives a
real Dommy document. This gem provides the QuickJS `Backend`; the
engine-agnostic bridge it plugs into (the `HostBridge` marshalling core and the
JS-side runtime) lives in the [`dommy`](https://github.com/takahashim/dommy) gem,
so other engines can reuse it.

The bridge presents a **spec-shaped JS DOM**, not bare proxies: `instanceof`,
prototype chains, `Object.prototype.toString` brands, constructable interfaces
(`new Event(...)`), custom elements (`class extends HTMLElement`), live
collections, and expandos all work — enough that the real
[`@hotwired/turbo`](https://github.com/hotwired/turbo) and
[`@hotwired/stimulus`](https://github.com/hotwired/stimulus) bundles load and
drive the DOM (turbo-stream + turbo-frame; Stimulus controllers, targets,
values, classes, actions, and outlets — see
`test/dommy/js/test_turbo_integration.rb` and
`test/dommy/js/test_stimulus_integration.rb`).

## Installation

In your `Gemfile`:

```ruby
gem "dommy-js-quickjs"
```

## Usage

```ruby
require "dommy"
require "dommy/js/quickjs"

win = Dommy.parse("<h1 class='title'>Hi</h1>")

rt = Dommy::Js::Quickjs::Runtime.new
rt.define_host_object("document", win.document)
rt.install_window(win) # exposes `window` + bare timer globals (setTimeout, ...)

rt.evaluate('document.querySelector(".title").textContent')        # => "Hi"
rt.execute('document.querySelector(".title").textContent = "Bye"') # mutates the DOM
win.document.query_selector(".title").text_content                 # => "Bye"
```

- `evaluate(js)` — evaluate an expression (or a `return`-using statement body) and
  return the value; DOM nodes come back as Dommy objects, Promises are awaited.
- `execute(js)` — run statements for side effects; drains microtasks.
- Timers ride Dommy's scheduler: `win.scheduler.advance_time(ms)` fires JS
  `setTimeout` / `setInterval` / `requestAnimationFrame` callbacks.
- `run_until_idle` — drive the event loop to quiescence: drains microtasks, then
  advances the scheduler to each due timer and drains again, in WHATWG order
  (microtasks before each timer), until nothing is pending. The one-call
  "settle everything" entry point after an eval (`max_iterations:` bounds
  self-rescheduling timer loops).

## What the JS sees

The JS-facing DOM behaves like a browser's, not like a plain object graph:

```js
const el = document.querySelector("button");
el instanceof HTMLElement                       // true (full prototype chain)
Object.prototype.toString.call(el)              // "[object HTMLButtonElement]"
el.constructor.name                             // "HTMLButtonElement"

new CustomEvent("x", { detail: 1 })             // constructable interfaces
el.dispatchEvent(new CustomEvent("x", {...}))   // events bubble; detail round-trips

for (const c of el.children) { /* ... */ }      // live, iterable collections
el.querySelectorAll("li").map(n => n.tagName)   // NodeList crosses as a JS array

el._state = { n: 1 }; el._state === el._state   // expandos keep their identity

class Card extends HTMLElement {                 // custom elements
  connectedCallback() { this.textContent = "hi"; }
}
customElements.define("x-card", Card);
```

Method-vs-property is taken from each Dommy class's `__js_method_names__`, so no
method list is maintained here.

## Running real frameworks (and testing components)

To run a real bundle you need the browser globals it reaches for and a way to
drive deferred work. `BrowserHarness` (under `test/support/`) packages this:

```ruby
h = Dommy::Js::BrowserHarness.new(
  "<body><div id='app'></div></body>",
  fetch_stub: { "http://localhost/frame" => { status: 200, contentType: "text/html", body: "..." } }
)
h.load_script("vendor/turbo.umd.js")   # runs the real bundle
h.execute("/* your app / interactions */")
h.pump                                  # drive microtasks + the scheduler clock
assert_empty h.errors                   # nothing was silently swallowed
```

The pieces it relies on are public Runtime API:

- `Runtime#install_browser_globals` — wire the bare globals real bundles use
  (`self` / `location` / `history` / `navigator` / storages / `CSS` / `fetch` /
  `addEventListener` / …), aliased onto the installed window.
- `Runtime#on_unhandled_rejection { |err| }` — surface promise rejections that
  reach the microtask queue with no handler. Frameworks swallow these; `err.backtrace`
  carries the JS stack, which is the difference between blind and one-shot debugging.
- `Runtime#on_log { |log| }` — observe `console.*` (`log.severity` / `log.to_s`).

### Preloading ES modules

A module the loader hands over as source is parsed again by every Runtime that
imports it. Register it once per process and later Runtimes read it in as
bytecode instead:

```ruby
Dommy::Js::Quickjs::Runtime.register_module("https://example.test/vendor/turbo.js", source: turbo_js)

rt = Dommy::Js::Quickjs::Runtime.new(preload_modules: ["https://example.test/vendor/turbo.js"])
rt.module_loader = ->(specifier, _importer) {
  {as: "https://example.test/vendor/turbo.js"} if specifier == "@hotwired/turbo"
}
```

- The name is the module's canonical name: the VM keys its module map by it,
  and the module's relative imports resolve against it. Register a page's
  module under its resolved URL.
- `source:` may be a Proc returning the source; it is read when a Runtime first
  preloads the module, and the bytecode is shared from then on. Each Runtime
  still gets its own instance, with its own module-level state.
- A preloaded module is found before the loader is asked for its name. A loader
  that returns `{as: name}` for another specifier (an importmap entry, say)
  lands on it too.
- A preloaded module's own imports are not preloaded; register each one you
  want cached. Naming a module that is not registered raises `ArgumentError`.
- Preloading bypasses the loader for that name, so do not preload a module the
  loader would refuse to some importers.

### Capybara

Requiring the adapter enables `execute_script` / `evaluate_script` on
`Capybara::Dommy::Driver` (capybara-dommy stays JS-free without it):

```ruby
require "dommy/js/quickjs/capybara"
```

## Limitations

- **Deterministic scheduler, no wall clock.** Async work (timers, `requestAnimationFrame`,
  framework "next repaint" deferral) only advances via `win.scheduler.advance_time(ms)` —
  drive it with `Runtime#run_until_idle`, `BrowserHarness#pump`, or manually.
  Selenium-style `done()` / real-time waits are not supported.
- **`fetch` is stub-based** via Dommy's `__fetchy_stub__` (a `{ url => entry }` map);
  there is no real network.
- **Event listeners** — both forms work: a function (`addEventListener("...", fn)`,
  closures intact) and the EventListener *object* form (`{ handleEvent }`, used by
  Stimulus). `removeEventListener` detaches by the same function/object identity.
- **Expandos are scoped to elements**, and the JS callback table is not evicted, so
  a very long-lived VM can grow unbounded.
- **DOM coverage is Dommy's.** A JS method/property works only where Dommy exposes
  it via the ABI (`__js_method_names__` / `__js_get__`); gaps surface as
  `undefined` / "not a function" (see `on_unhandled_rejection`).

## Development

Run `bin/setup` to install dependencies, then `rake test`. `bin/console` opens an
interactive prompt.

The real-framework integration tests are skipped unless their bundle is
vendored under `test/fixtures/`:

```bash
curl -sL https://unpkg.com/@hotwired/turbo@8/dist/turbo.es2017-umd.js \
  -o test/fixtures/turbo.umd.js
curl -sL https://unpkg.com/@hotwired/stimulus@3/dist/stimulus.umd.js \
  -o test/fixtures/stimulus.umd.js
```

### Conformance suites

Two tasks run real third-party test corpora against the bridge and report a
pass rate — the lens that pins how faithfully the bridge hosts the platform:

```bash
rake wpt:conformance[filter]        # Web Platform Tests (vendored under test/fixtures/wpt)
rake stimulus:conformance[filter]   # @hotwired/stimulus's own QUnit suite
```

The Stimulus suite is vendored as a single bundle (`test/fixtures/
stimulus-tests.umd.js`) run through a small QUnit shim; each test runs in its
own fresh VM. Regenerate the bundle with `script/build_stimulus_tests.sh`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/takahashim/dommy-js-quickjs.
