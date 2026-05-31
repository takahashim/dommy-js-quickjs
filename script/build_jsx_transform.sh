#!/usr/bin/env bash
# Regenerate test/fixtures/jsx-transform.umd.js — a minimal JSX→JS transpiler
# (sucrase) bundled into a single IIFE that exposes `globalThis.transformJSX`.
#
# Sucrase is a tiny, JSX/TS-focused alternative to Babel: the bundle is ~200 KB
# vs @babel/standalone's ~3 MB, since it carries only the JSX transform. At run
# time the bundle is loaded into the QuickJS VM (pure Ruby + RubyGems — no Node,
# no native binary); Node/esbuild are only needed here to (re)build it.
#
#   script/build_jsx_transform.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/test/fixtures/jsx-transform.umd.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
npm init -y >/dev/null 2>&1
npm install sucrase >/dev/null 2>&1
# `production: true` emits classic React.createElement calls (no dev __source/
# __self props), which the vendored React UMD build consumes.
echo "import { transform } from 'sucrase';
globalThis.transformJSX = (code) => transform(code, { transforms: ['jsx'], production: true }).code;" > entry.js

npx --yes esbuild@0.24.0 entry.js --bundle --format=iife --minify --outfile="$OUT"
echo "Wrote $OUT ($(wc -c < "$OUT") bytes)"
