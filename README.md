# Dommy::Js::Quickjs

A QuickJS backend that runs JavaScript against a [Dommy](https://github.com/takahashim/dommy) DOM.

JavaScript executes in an embedded QuickJS VM (via the [`quickjs`](https://github.com/hmsk/quickjs.rb) gem). DOM nodes are bridged to JS as ES `Proxy` objects whose property/method access routes into Dommy's `__js_get__` / `__js_set__` / `__js_call__` ABI, so JS can drive a real Dommy document. The QuickJS-specific code is isolated in a small `Backend`; the rest is engine-agnostic.

## Installation

Not yet released. From git, in your `Gemfile`:

```ruby
gem "dommy-js-quickjs", git: "https://github.com/takahashim/dommy-js-quickjs"
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

- `evaluate(js)` — evaluate an expression (or a `return`-using statement body) and return the value; DOM nodes come back as Dommy objects, Promises are awaited.
- `execute(js)` — run statements for side effects; drains microtasks.
- Timers ride Dommy's scheduler: `win.scheduler.advance_time(ms)` fires JS `setTimeout` / `setInterval` callbacks.

### Capybara

Requiring the adapter enables `execute_script` / `evaluate_script` on `Capybara::Dommy::Driver` (capybara-dommy stays JS-free without it):

```ruby
require "dommy/js/quickjs/capybara"
```

## Limitations

- **`evaluate_async_script` has no real-time async.** It awaits Promises/microtasks like `evaluate_script`, but the Selenium-style `done()`-callback and timer-deferred completions are not supported: Dommy's scheduler is deterministic (time advances only via `advance_time`), so there is no wall clock to wait on.
- **Event listeners must be functions.** `addEventListener("...", fn)` works (closures intact, and `removeEventListener` with the same function detaches it), but the object form `addEventListener("...", { handleEvent })` is not supported.

Which names are methods (vs. properties) is taken from each Dommy class's `__js_method_names__`, so no method list is maintained here.

## Development

Run `bin/setup` to install dependencies, then `rake test`. `bin/console` opens an interactive prompt.

## Contributing

Bug reports and pull requests are welcome at https://github.com/takahashim/dommy-js-quickjs.
