#!/usr/bin/env bash
# Compare Dommy vs happy-dom vs jsdom on Dommy's vendored WPT corpus.
#   cd script/wpt-compare && npm install && ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
export WPT="$ROOT/test/fixtures/wpt"
export TH="$ROOT/test/fixtures/testharness.js"

# 1. Dommy per-file results
( cd "$ROOT" && bundle exec ruby -e '
  $LOAD_PATH.unshift File.expand_path("lib"); require "dommy/js/quickjs"; require "dommy"
  require_relative "test/support/wpt_runner"
  Dommy::Js::WptRunner.manifest.each do |rel|
    res = Dommy::Js::WptRunner.run(rel) rescue nil
    p = res ? res.count { |r| r.status == 0 } : 0
    puts "#{rel}\t#{res ? "#{p}/#{res.size}" : "ERR"}"
  end' ) > dommy-results.txt
cut -f1 dommy-results.txt > manifest.txt

# 2. happy-dom + jsdom, one subprocess per file (survives hangs)
for engine in happydom jsdom; do
  : > "$engine-results.txt"
  xargs -P 6 -I{} sh -c "timeout 12 node one.mjs $engine '{}' 2>/dev/null || printf '%s\tHANG\n' '{}'" \
    < manifest.txt >> "$engine-results.txt"
done

# 3. Aggregate + deltas
node aggregate.mjs
node deltas.mjs
