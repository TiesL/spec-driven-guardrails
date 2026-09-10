#!/usr/bin/env bash
# S85 — A pre-migration project is reported per row, with a tracking issue.
# Dekt: F6, W42/#114

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a real git project with an old-format answer file — two answered
# rows (one ja, one nee) that are not otherwise pending.
project="$(vers_project pre-migratie)"
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoptie van gedeelde workflow-wijzigingen

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| ci-conventie | ja | 2026-01-01 | verouderd antwoord |
| deploy-guards | nee | 2026-01-01 | verouderd antwoord |
EOF

# A fake gh that reports no matching existing issue, records the exact
# "issue create" call, and confirms it ran from the project's own
# directory (not some other repo).
gh_log="$SANDBOX/gh-calls.txt"
: > "$gh_log"
fakebin="$(fake_gh_bin '
echo "$*" >> "'"$gh_log"'"
case "$*" in
  "issue list --state open --json body --jq .[].body")
    printf ""
    exit 0 ;;
  "issue create --title "*)
    exit 0 ;;
esac
exit 1
')"

# When: pending-changes.sh runs.
uitvoer="$(PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"

# Then: each old-format row is named individually, with a bullet that does
# not collide with the pending-question list's own "  - " prefix (that
# prefix is what test/lib.sh's openstaande_ids() greps for).
assert_contains "S85 — mentions the pre-migration notice" "pre-migration format" "$uitvoer"
assert_contains "S85 — names ci-conventie" "* ci-conventie" "$uitvoer"
assert_contains "S85 — names deploy-guards" "* deploy-guards" "$uitvoer"
if printf '%s\n' "$uitvoer" | grep -qE '^  - (ci-conventie|deploy-guards)( |$)'; then
  fail "S85 — an already-answered old-format row was listed as a pending question"
fi

# And: those two rows do not appear in the pending set at all — they have
# real answers, just in the old vocabulary.
gekregen="$SANDBOX/gekregen.txt"
openstaande_ids "$project" > "$gekregen"
if grep -qx 'ci-conventie' "$gekregen" || grep -qx 'deploy-guards' "$gekregen"; then
  fail "S85 — an already-answered old-format row was swept into the pending ID set"
fi

# And: a tracking issue was filed on the project's own repo.
assert_contains "S85 — reports the tracking issue" "Filed a tracking issue" "$uitvoer"
[ "$(grep -c '^issue create' "$gh_log")" -eq 1 ] \
  || fail "S85 — expected exactly one 'gh issue create' call, got $(grep -c '^issue create' "$gh_log")"
grep -q 'ci-conventie' "$gh_log" || fail "S85 — the issue body/title does not mention ci-conventie"

# When: pending-changes.sh runs again, but this time an open issue with the
# marker already exists.
gh_log2="$SANDBOX/gh-calls-2.txt"
: > "$gh_log2"
fakebin2="$(fake_gh_bin '
echo "$*" >> "'"$gh_log2"'"
case "$*" in
  "issue list --state open --json body --jq .[].body")
    printf "bestaande body\\n<!-- workflow-adoptie-migratie -->"
    exit 0 ;;
  "issue create --title "*)
    exit 0 ;;
esac
exit 1
')"
PATH="$fakebin2:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$project" > /dev/null 2>&1

# Then: no second issue gets created — idempotent, marker-driven.
[ "$(grep -c '^issue create' "$gh_log2")" -eq 0 ] \
  || fail "S85 — a second tracking issue was created even though one already exists"

# And: a project directory that is not its own git root (e.g. a directory
# nested inside a different repo, like the frozen nulmeting fixtures) never
# triggers a gh call at all — never write to the wrong repository.
geneste_map="$project/binnenin"
mkdir -p "$geneste_map"
cp "$project/WORKFLOW-ADOPTIE.md" "$geneste_map/WORKFLOW-ADOPTIE.md"
gh_log3="$SANDBOX/gh-calls-3.txt"
: > "$gh_log3"
fakebin3="$(fake_gh_bin '
echo "$*" >> "'"$gh_log3"'"
exit 1
')"
PATH="$fakebin3:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$geneste_map" > /dev/null 2>&1
[ -s "$gh_log3" ] && fail "S85 — gh was called for a directory that is not its own git root"

test_klaar
