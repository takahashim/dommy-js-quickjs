#!/usr/bin/env bash
# Refresh the vendored WPT tree from upstream, all of it at one revision.
#
# The tree under test/fixtures/wpt grew file by file over many sessions, from
# whatever upstream happened to be that day, and nothing recorded which commit
# each file came from. This script makes that reproducible: every vendored file
# is fetched at the single revision named in UPSTREAM_REVISION, so a refresh is
# "move the pin, re-run this" rather than another hand checkout.
#
#   script/vendor_wpt.sh --dry-run          # what would change at the pin
#   script/vendor_wpt.sh --rev <sha>        # move the pin and refresh
#   script/vendor_wpt.sh --rev master       # resolve master to a sha, then that
#
# Files listed in LOCAL_FILES are ours, not upstream's (harness shims written
# for the single-VM runner), and are never touched.
#
# The script only refreshes files that are already vendored. It never adds a
# file upstream has and we do not, because vendoring a new test is a decision
# about what the suite covers. It reports what upstream no longer has and
# leaves the removal to a human.
#
# Written for bash 3.2 (macOS): no mapfile, no associative arrays.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$REPO_ROOT/test/fixtures/wpt"
REVISION_FILE="$VENDOR_DIR/UPSTREAM_REVISION"
LOCAL_FILES="$VENDOR_DIR/LOCAL_FILES"
CACHE="${WPT_VENDOR_CACHE:-$REPO_ROOT/tmp/wpt-upstream}"
UPSTREAM_URL="https://github.com/web-platform-tests/wpt.git"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

dry_run=false
rev=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --rev) rev="${2:-}"; shift ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$rev" ]; then
  [ -f "$REVISION_FILE" ] || { echo "no $REVISION_FILE yet; pass --rev <sha|master>" >&2; exit 2; }
  rev="$(grep -v '^#' "$REVISION_FILE" | tr -d '[:space:]' | head -1)"
fi

# The set to refresh: every vendored file except our own bookkeeping and the
# harness shims we wrote ourselves.
(cd "$VENDOR_DIR" && find . -type f | sed 's|^\./||' | sort) |
  grep -vx 'UPSTREAM_REVISION' | grep -vx 'LOCAL_FILES' > "$WORK/vendored"
if [ -f "$LOCAL_FILES" ]; then
  sed 's/#.*//' "$LOCAL_FILES" | sed 's/[[:space:]]//g' | grep -v '^$' | sort > "$WORK/local"
else
  : > "$WORK/local"
fi
comm -23 "$WORK/vendored" "$WORK/local" > "$WORK/refresh"

echo "vendored: $(wc -l < "$WORK/vendored" | tr -d ' ') files, $(wc -l < "$WORK/local" | tr -d ' ') of them ours (never refreshed)"

# A blobless, checkout-less mirror: we pay for the tree, not for every blob in
# WPT's history, and pull blobs only for the paths we actually vendor.
if [ ! -d "$CACHE/.git" ]; then
  echo "cloning $UPSTREAM_URL into $CACHE (blobless; a few minutes the first time)"
  git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$CACHE"
fi
git -C "$CACHE" fetch --filter=blob:none origin "$rev" >/dev/null 2>&1 ||
  git -C "$CACHE" fetch --filter=blob:none origin >/dev/null

resolved="$(git -C "$CACHE" rev-parse "FETCH_HEAD^{commit}" 2>/dev/null ||
            git -C "$CACHE" rev-parse "$rev^{commit}")"
echo "upstream revision: $resolved"
echo "                   $(git -C "$CACHE" log -1 --format='%ad %s' --date=short "$resolved" | cut -c1-72)"

same=0; differs=0; gone=0
: > "$WORK/changed"; : > "$WORK/gone"
while IFS= read -r f; do
  if ! git -C "$CACHE" show "$resolved:$f" > "$WORK/blob" 2>/dev/null; then
    gone=$((gone + 1)); echo "$f" >> "$WORK/gone"; continue
  fi
  if cmp -s "$WORK/blob" "$VENDOR_DIR/$f"; then
    same=$((same + 1))
  else
    differs=$((differs + 1)); echo "$f" >> "$WORK/changed"
    $dry_run || cp "$WORK/blob" "$VENDOR_DIR/$f"
  fi
done < "$WORK/refresh"

echo
echo "unchanged upstream : $same"
echo "would update       : $differs"
echo "kept (ours)        : $(wc -l < "$WORK/local" | tr -d ' ')"
echo "gone from upstream : $gone"

[ -s "$WORK/changed" ] && { echo; echo "updated:"; sed 's/^/  /' "$WORK/changed"; }
[ -s "$WORK/gone" ] && {
  echo; echo "no longer at this revision (renamed or removed upstream; decide per file):"
  sed 's/^/  /' "$WORK/gone"
}

if $dry_run; then
  echo; echo "(dry run; nothing written)"
else
  { echo "# The upstream web-platform-tests revision every file here was taken from."
    echo "# Refresh with: script/vendor_wpt.sh --rev <sha>"
    echo "$resolved"
  } > "$REVISION_FILE"
  echo; echo "wrote $REVISION_FILE"
  echo "re-run the suite: a baseline that rose is an improvement to fold in, and a"
  echo "test whose expectation upstream has not caught up on goes in expected: with a comment."
fi
