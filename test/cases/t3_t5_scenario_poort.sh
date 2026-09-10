#!/usr/bin/env bash
# T3, T5 — link 2 (scenario -> issue) as a gate in pre-merge-review (W20).
# Covers: F13
#
# "Is this scenario named by an issue" is a strict field match: only
# an issue's **Covers:** field counts, an ID that happens to appear in a
# sentence does not (T5). T3: an uncovered scenario is named explicitly.
#
# W42/#114: an issue's **Dekt:** field (pre-migration, historical/closed
# issues) counts exactly the same as **Covers:** — a permanent exception
# for this one script's issue-reading, confirmed with Ties, since rewriting
# the body of every historical issue is out of scope for this migration.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/scenario-poort.sh"
[ -x "$script" ] || { fail "T3/T5 — skills/pre-merge-review/scenario-poort.sh is missing or not executable"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

project="$SANDBOX/project"
mkdir -p "$project"
cat > "$project/TEST-SCENARIOS.md" <<'EOF'
### S1 — wordt alleen in lopende tekst genoemd, niet in een dekkingsveld

### S2b — staat wél in een Covers-veld, met staart-letter

### S3 — wordt door geen enkel issue genoemd

### S4 — staat in een pre-migratie Dekt-veld (historisch issue, W42/#114)
EOF

# One issue: mentions S1 loosely in the body (not a reference), covers S2b
# via the current **Covers:** field. A second, historical issue still
# carries the pre-migration **Dekt:** field and covers S4 through it. S3
# does not appear in any body.
fakebin="$(fake_gh_bin '
case "$*" in
  "issue list --state all --limit 500 --json body --jq .[].body")
    printf "%s\n" "we hebben inmiddels s1 varianten getest"
    printf "%s\n" "**Covers:** S2b"
    printf "%s\n" "**Dekt:** S4"
    exit 0 ;;
esac
exit 1
')"

uitvoer="$(PATH="$fakebin:$PATH" "$script" "$project" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T3/T5 — the gate failed unexpectedly (exit $status): $uitvoer"

# T3 — S3 is uncovered and is named explicitly.
assert_contains "T3 — S3 is named as uncovered" "S3" "$uitvoer"

# T5 — the loose text mention of s1 does not count as coverage: S1 thus
# also stays uncovered.
assert_contains "T5 — S1 stays uncovered (running prose does not count)" "S1" "$uitvoer"

# T5 — S2b does count, via the current Covers: field: no "S2b ... uncovered" line.
case "$uitvoer" in
  *"S2b wordt door geen enkel issue gedekt"*)
    fail "T5 — S2b (covered via the Covers: field) was reported as uncovered anyway" ;;
esac

# W42/#114 — S4 also counts, via the pre-migration Dekt: field on a
# historical issue: no "S4 ... uncovered" line either.
case "$uitvoer" in
  *"S4 wordt door geen enkel issue gedekt"*)
    fail "W42/#114 — S4 (covered via a historical Dekt: field) was reported as uncovered anyway" ;;
esac

# AC4 — the gate does not fail blockingly without gh.
padzondergh="$(pad_zonder_gh)"
uitvoer_geengh="$(PATH="$padzondergh" "$script" "$project" 2>&1)"; status_geengh=$?
[ "$status_geengh" -eq 0 ] || fail "AC4 — without gh the gate gave exit $status_geengh instead of 0"
assert_contains "AC4 — a warning appears without gh" "waarschuwing" "$uitvoer_geengh"

test_klaar
