# wpt-compare

Runs Dommy's vendored WPT corpus (`test/fixtures/wpt`, the same 245-file manifest
`WptRunner` uses) under **jsdom** and **happy-dom**, and compares fully-green /
runnable counts with Dommy. Backs `docs/dom-library-comparison.md`.

```
cd script/wpt-compare
npm install          # jsdom + happy-dom
./run.sh             # writes {dommy,happydom,jsdom}-results.txt, prints tables
```

Caveats (see the doc): the corpus is Dommy-selected; this harness inlines
`<script src>` helpers and does not inject Node globals (e.g. TextEncoder) into
jsdom's window, so jsdom's encoding numbers are understated. The verified,
harness-independent findings are happy-dom's cross-script scope isolation and
Dommy's accessibility lead.
