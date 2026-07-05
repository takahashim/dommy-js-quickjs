#!/usr/bin/env bash
# Regenerate test/fixtures/turbo-tests.umd.js — the @hotwired/turbo UNIT suite
# (src/tests/unit/*) bundled into a single IIFE runnable in the QuickJS VM.
#
# Only the unit suite is portable: Turbo's functional/ and integration/ tests
# drive a real browser via Playwright against a Koa dev server (src/tests/
# server.mjs) with cross-page navigation, which a single QuickJS VM can't host.
# Those behaviors are covered instead by hand-written cases in
# test/dommy/js/test_turbo_integration.rb.
#
# Requirements: git, node + npx (esbuild is fetched on demand).
#
#   script/build_turbo_tests.sh [turbo-git-ref]
#
# Steps (mirrors script/build_stimulus_tests.sh):
#   1. Clone the source (its tests live in src/tests, not the npm package).
#   2. Prepend `__setModule("<file>")` to each unit file so the mocha shim can
#      group each file's top-level test()s under that file name (the files
#      don't wrap tests in suite()). The marker runs after the file's own
#      imports (ES imports hoist) but before its test()/setup() calls.
#   3. Generate an entry importing every unit file, then esbuild-bundle to an
#      IIFE. `@open-wc/testing` is aliased to test/support/openwc_testing_shim.js
#      (Turbo's unit tests only use its `assert`, which mocha_shim.js provides);
#      the mocha TDD globals come from the shim at run time.
set -euo pipefail

REF="${1:-v8.0.23}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/test/fixtures/turbo-tests.umd.js"
OPENWC_SHIM="$ROOT/test/support/openwc_testing_shim.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning hotwired/turbo @ $REF ..."
git clone --depth 1 --branch "$REF" -q https://github.com/hotwired/turbo.git "$TMP/turbo"
cd "$TMP/turbo"

# Turbo's morphing imports idiomorph (its only runtime dependency reachable from
# the unit suite; everything else — express/multer/playwright — is functional/
# server-only and never imported by src/tests/unit). Install just that so
# esbuild can bundle it, matching the version Turbo pins.
IDIOMORPH_VERSION="$(ruby -rjson -e 'puts JSON.parse(File.read("package.json")).dig("dependencies", "idiomorph") || "~0.7.4"')"
echo "Installing idiomorph@$IDIOMORPH_VERSION ..."
npm install --no-save --no-audit --no-fund --loglevel=error "idiomorph@$IDIOMORPH_VERSION"

# (2) per-file module marker + (3) explicit entry
ruby -e '
files = Dir.chdir("src/tests/unit") { Dir["*_tests.js"].sort }
files.each do |f|
  path = "src/tests/unit/#{f}"
  name = File.basename(f, ".js")
  src = File.read(path)
  File.write(path, %(globalThis.__setModule(#{name.inspect});\n) + src)
end
File.write("src/tests/conformance.entry.js",
  files.each_with_index.map { |f, i| %(import "./unit/#{f}") }.join("\n") + "\n")
puts "entry: #{files.size} unit files"
'

# (3) bundle (Turbo ships no tsconfig.json; esbuild's defaults handle the .ts src)
npx --yes esbuild@0.24.0 src/tests/conformance.entry.js \
  --bundle --format=iife --target=es2017 \
  --alias:@open-wc/testing="$OPENWC_SHIM" \
  --outfile="$OUT"

echo "Wrote $OUT"
