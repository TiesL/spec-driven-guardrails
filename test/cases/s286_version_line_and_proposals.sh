#!/usr/bin/env bash
# S286 — the README releases table row for the newest dated CHANGELOG release matches that heading, and that release has one dated heading matching its tag (#420 AC3; #474 AC6, AC8; #585).
# Covers: F15, F16

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

# Arm 1: exactly one README table row whose first cell is V; its Date cell equals the
# CHANGELOG heading date and its Theme cell equals the heading title. No bold version
# token (**vX.Y.Z**) before the first '## ' heading of README.md. Earlier rows' themes are free text.
hdate0="$(sed -E 's/.*\(([0-9-]{10})\)$/\1/' <<<"$head_line")"
htitle="$(sed -E 's/^## v[0-9]+\.[0-9]+\.[0-9]+ — (.*) \([0-9-]{10}\)$/\1/' <<<"$head_line")"
rows="$(grep -E "^\| *\`?$V\`? *\|" "$r/README.md")"
nrows="$(grep -c . <<<"$rows")"
[ "$nrows" -eq 1 ] || fail "S286 — README.md has $nrows table rows for $V, expected 1 (newest dated CHANGELOG release)"
rdate="$(awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}' <<<"$rows")"
rtheme="$(awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}' <<<"$rows")"
[ "$rdate" = "$hdate0" ] || fail "S286 — README.md row for $V has date '$rdate', CHANGELOG heading date is '$hdate0'"
[ "$rtheme" = "$htitle" ] || fail "S286 — README.md row for $V has theme '$rtheme', CHANGELOG heading title is '$htitle'"
bold="$(awk '/^## /{exit} {print}' "$r/README.md" | grep -oE '\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*' | head -n 1)"
[ -z "$bold" ] || fail "S286 — README.md has a bold version token '$bold' before the first '## ' heading (hardcoded version line must not return)"

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

# Arm 4: v0.2.0 appears on 5 README lines: 4 historical mentions plus the one table row.
old="$(grep -cF 'v0.2.0' "$r/README.md")"
[ "$old" -eq 5 ] || fail "S286 — README.md has $old lines mentioning v0.2.0, expected 5 (4 historical + 1 table row)"

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
