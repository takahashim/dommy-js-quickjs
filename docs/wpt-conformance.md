# WPT conformance

The vendored Web Platform Tests corpus under `test/fixtures/wpt/` is run against
the bridge by `WptRunner` (`test/support/wpt_runner.rb`) and reported by:

```
bundle exec rake wpt:conformance          # whole corpus
bundle exec rake "wpt:conformance[url]"    # filter by path substring
```

`WptRunner` handles both WPT file shapes: `.any.js` / `.window.js` scripts
(resolving `// META: script=` includes and serving `fetch("resources/…")` data
files from disk via the fetch stub) and `.html` tests (the file becomes the
document; inline `<script>` blocks are the test, non-testharness `<script src>`
helpers are resolved against the vendored tree). See `WptHarness` for how a
synthetic `load` event drives testharness completion.

## Snapshot (2026-05-30)

```
  dom        33/2261  (1.5%)
  url        75/109   (68.8%)
  total     108/2370  (4.6%)   — 6 files fully green
```

The `dom` aggregate is dominated by two data-driven mega-files —
`Element-classlist.html` (1420 subtests) and `Document-createElementNS.html`
(596) — that fail almost entirely on a *single* systemic gap each. The number to
watch per area is the per-file rate, not the rolled-up percentage: a handful of
fixes below unlock thousands of subtests.

## Dommy-side gap backlog (ordered by ROI)

These are real conformance gaps the corpus surfaced. Most are Dommy-side; a few
are bridge-side (noted). Batch target.

### Promise/A+ — unblocks data-driven `url-constructor` (~700) + `url-origin`
- **`PromiseValue#then` does not adopt a returned thenable.** A `.then` callback
  that returns another promise (e.g. `fetch().then(r => r.json()).then(data …)`)
  should resolve to that promise's value; instead the next handler receives the
  promise object itself. QuickJS-native promises flatten correctly — only
  Dommy's `PromiseValue` chain doesn't. Blocks every `fetch().then(json).then()`
  pattern, hence both data-driven URL tests report a single rejected
  `promise_test`.

### Live `classList` — unblocks ~1400 `Element-classlist` subtests
- **`classList` (DOMTokenList) is not live over the `class` attribute.**
  `setAttribute("class", …)` / `removeAttribute("class")` don't reflect in
  `classList.length` / `.contains` (stale token list). Must be a live view.

### createElement / createElementNS / namespaces
- `createElementNS` non-HTML namespaces must preserve case: `createElementNS(SVG,
  "svg").nodeName` should stay `"svg"`, not be upper-cased; likewise `tagName`
  for SVG/MathML/other namespaces.
- Invalid qualified name (`"x:b"` in an HTML document context, empty name, bad
  productions) must raise `DOMException` `InvalidCharacterError` /
  `INVALID_CHARACTER_ERR`.
- `createElement(undefined)` path expects `HTMLUnknownElement` to exist as a
  seeded interface (test does `instanceof` against it → "invalid instanceof
  right operand").

### Node naming / node types
- `Text` node `nodeName` must return the string `"#text"` (currently a
  non-string object crosses the bridge); `Comment` → `"#comment"`.

### Attributes
- `toggleAttribute` is missing ("not a function").
- Bad qualifiedName → `INVALID_CHARACTER_ERR`.

### URLSearchParams
- Argument coercion: `append(null, null)` / `delete` / `has` must `ToString`
  arguments — `null` → `"null"`, not `""`.
- `has(name, value)` two-argument form (and `delete(name, value)`); `has`
  "basics" currently returns false where true is expected.
- `forEach(cb)` must accept a JS callback — currently raises
  `wrong argument type Dommy::Js::HostCallback (expected Proc)` (**bridge/Dommy
  boundary**); iteration order + live mutation during `for…of`.
- Constructor: sequence-of-sequences validation (`new URLSearchParams([[1]])`
  must throw), unpaired-surrogate handling.
- `application/x-www-form-urlencoded` serialization must **not** percent-encode
  `*` (`a=*-._` not `a=%2A-._`); empty-name ordering (`a=b&c=d&e=`).
- URL query parsing rejects non-ASCII ("URI must be ascii only") — must accept /
  percent-encode; surrogate ordering in `sort`.

### URL statics
- `URL.parse(undefined, base)` / `URL.canParse(undefined, base)` for the
  relative-without-base case should return `null` / `false`; currently
  `URL.parse` returns a Node-like object ("Node object of unknown type" crosses
  the bridge) and `canParse` returns `true`.

### Interfaces / bigger features (lower priority)
- Seed `NodeList` interface (getElementsByClassName interface check).
- `document.implementation.createDocument` / foreign documents /
  `createDocumentType` — needed by `Node-isEqualNode` and WPT's `dom/common.js`
  setup (those tests are not yet vendored because their setup throws without it).
- `DocumentFragment#childNodes` / `Document` node dehydration ("Node object of
  unknown type", "Illegal constructor") — **bridge-side** dehydration coverage.
