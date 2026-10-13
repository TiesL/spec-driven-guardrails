#!/usr/bin/env bash
# S286 — the README current-version line equals the newest dated CHANGELOG release, and that release has one dated heading matching its tag (#420 AC3; #474 AC6, AC8).
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"
cl="$r/CHANGELOG.md"

# Derive V: the first dated release heading ('## Unreleased' and undated headings are skipped).
head_line="$(grep -E -m1 '^## v[0-9]+\.[0-9]+\.[0-9]+ — .*\([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$cl")"
[ -n "$head_line" ] || fail "S286 — CHANGELOG.md has no dated '## vX.Y.Z — ... (YYYY-MM-DD)' heading"
V="$(sed -E 's/^## (v[0-9]+\.[0-9]+\.[0-9]+) .*/\1/' <<<"$head_line")"

# Arm 1: README line 7 bold token equals **V**.
line7="$(sed -n 7p "$r/README.md")"
tok="$(grep -oE '\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*' <<<"$line7" | head -n 1)"
[ "$tok" = "**$V**" ] || fail "S286 — README.md line 7 token is '$tok', expected '**$V**' (newest dated CHANGELOG release)"

# Arm 2: exactly one heading begins '## V '.
n="$(grep -c "^## $V " "$cl")"
[ "$n" -eq 1 ] || fail "S286 — CHANGELOG.md has $n headings beginning '## $V ', expected 1"

# Arm 3: heading date equals the tag date when the tag resolves.
hdate="$(sed -E 's/.*\(([0-9-]{10})\)$/\1/' <<<"$head_line")"
if git -C "$r" rev-parse -q --verify "refs/tags/$V" >/dev/null 2>&1; then
  tdate="$(git -C "$r" log -1 --format=%ad --date=short "$V")"
  [ "$hdate" = "$tdate" ] || fail "S286 — heading date $hdate differs from tag $V date $tdate"
else
  echo "S286 — note: tag $V not in this clone, date arm skipped"
fi

# Arm 4: four historical v0.2.0 lines outside line 7, unchanged.
old="$(sed '7d' "$r/README.md" | grep -cF 'v0.2.0')"
[ "$old" -eq 4 ] || fail "S286 — README.md has $old historical v0.2.0 lines outside line 7, expected 4 (unchanged)"

# Arm 5: a released version is no proposal (CHANGELOG '## V' section and README only;
# TEST-SCENARIOS.md quotes the tokens as test data and is not scanned).
{
  changelog_section "$cl" "## $V" | grep -F "$V"
  grep -F "$V" "$r/README.md"
} 2>/dev/null | grep -Ei 'propos|unreleased' > "${TMPDIR:-/tmp}/s286.$$" || true
if [ -s "${TMPDIR:-/tmp}/s286.$$" ]; then
  fail "S286 — $V is described as a proposal or unreleased on: $(head -n 3 "${TMPDIR:-/tmp}/s286.$$")"
fi
rm -f "${TMPDIR:-/tmp}/s286.$$"

test_done
