#!/usr/bin/env bash
# Regenerate test/fixtures/stimulus-tests.umd.js — the @hotwired/stimulus QUnit
# suite bundled into a single IIFE script runnable in the QuickJS VM.
#
# Requirements: git, node + npx (esbuild is fetched on demand).
#
#   script/build_stimulus_tests.sh [stimulus-git-ref]
#
# Stimulus runs its tests under Karma+webpack; we replicate the inputs:
#   1. Clone the source (its tests live in src/tests, not the npm package).
#   2. Replace the webpack-only `require.context` entry with an explicit entry
#      that imports every *_tests.ts module and calls defineModule().
#   3. Patch TestCase.testPropertyNames to use getOwnPropertyNames instead of
#      Object.keys — native ES2017 class methods are non-enumerable, whereas
#      Stimulus's own es5 (tsc) build emits enumerable prototype assignments.
#      The two are equivalent (own, string-keyed); this just lets the esbuild
#      ES2017 bundle discover the `test ...` methods.
#   4. esbuild-bundle to an IIFE that references a global QUnit (the shim in
#      test/support/qunit_shim.js provides it at run time).
set -euo pipefail

REF="${1:-v3.2.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/test/fixtures/stimulus-tests.umd.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning hotwired/stimulus @ $REF ..."
git clone --depth 1 --branch "$REF" -q https://github.com/hotwired/stimulus.git "$TMP/stimulus"
cd "$TMP/stimulus"

# (3) enumerability patch
ruby -i -pe 'sub(/Object\.keys\(this\.prototype\)/, "Object.getOwnPropertyNames(this.prototype)")' \
  src/tests/cases/test_case.ts

# (2) explicit entry replacing require.context
ruby -e '
mods = Dir.chdir("src/tests") { Dir["modules/**/*_tests.ts"].sort }
imports = mods.each_with_index.map { |m, i| %(import M#{i} from "./#{m.sub(/\.ts$/, "")}") }
File.write("src/tests/conformance.entry.ts",
  imports.join("\n") + "\n" +
  "const MODULES = [#{mods.size.times.map { |i| "M#{i}" }.join(", ")}]\n" +
  "MODULES.forEach((c) => c.defineModule())\n")
puts "entry: #{mods.size} modules"
'

# (4) bundle
npx --yes esbuild@0.24.0 src/tests/conformance.entry.ts \
  --bundle --format=iife --target=es2017 --tsconfig=tsconfig.json \
  --outfile="$OUT"

echo "Wrote $OUT"
