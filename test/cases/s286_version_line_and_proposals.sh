#!/usr/bin/env bash
# S286 — the current-version line is v0.3.0 and v0.4.0 only appears as a proposal (#420, AC3, AC6).
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"

# README line 7 names v0.3.0 in bold; the four historical v0.2.0 lines stay.
line7="$(sed -n 7p "$r/README.md")"
grep -qF '**v0.3.0**' <<<"$line7" || fail "S286 — README.md line 7 does not carry the bold token **v0.3.0**"
old="$(sed '7d' "$r/README.md" | grep -cF 'v0.2.0')"
[ "$old" -eq 4 ] || fail "S286 — README.md has $old historical v0.2.0 lines outside line 7, expected 4 (unchanged)"

# No v0.4.0 heading; every v0.4.0 line says it is a proposal.
grep -q '^## v0\.4\.0' "$r/CHANGELOG.md" && fail "S286 — CHANGELOG.md has a '## v0.4.0' heading"
# TEST-SCENARIOS.md is left out: it quotes the token to specify this check.
hits="$(grep -rnF 'v0.4.0' "$r"/*.md "$r/skills" 2>/dev/null | grep -v "^$r/TEST-SCENARIOS.md:")"
while IFS= read -r l; do
  [ -n "$l" ] || continue
  grep -qi 'propos' <<<"$l" || echo "$l"
done <<<"$hits" > "${TMPDIR:-/tmp}/s286.$$"
if [ -s "${TMPDIR:-/tmp}/s286.$$" ]; then
  fail "S286 — v0.4.0 appears without 'propos' on: $(head -n 3 "${TMPDIR:-/tmp}/s286.$$")"
fi
rm -f "${TMPDIR:-/tmp}/s286.$$"

test_done
