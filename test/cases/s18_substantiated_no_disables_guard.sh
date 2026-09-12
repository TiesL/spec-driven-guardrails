#!/usr/bin/env bash
# S18 — A substantiated `nee` disables the merge guard, without a network call.
# Covers: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project uitgeschakeld)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

cat > "$project/WORKFLOW-ADOPTIE.md" <<EOF
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| kwaliteitsreview-voor-merge | nee | 2026-01-01 | dit project heeft geen PR's, alleen directe commits door één persoon |
EOF

# If the guard were to call gh anyway, this file would reveal that.
sentinel="$SANDBOX/gh-was-aangeroepen"
fakebin="$(fake_gh_bin '
touch "'"$sentinel"'"
exit 1
')"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S18 — expected pass-through (exit 0), got $status. Output: $uitvoer"
[ ! -e "$sentinel" ] || fail "S18 — the guard called gh while the row is set to 'nee'; that should stay local"

# And: the same holds for the post-migration format (W42/#114) — new
# filename, new ID, new value.
project2="$(fresh_project uitgeschakeld-nieuw)"
git -C "$project2" commit -q --allow-empty -m start
git -C "$project2" checkout -q -b feature/werk

cat > "$project2/WORKFLOW-ADOPTION.md" <<EOF
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| quality-review-before-merge | no | 2026-01-01 | dit project heeft geen PR's, alleen directe commits door één persoon |
EOF

sentinel2="$SANDBOX/gh-was-aangeroepen-nieuw"
fakebin2="$(fake_gh_bin '
touch "'"$sentinel2"'"
exit 1
')"

invoer2='{"tool_name":"Bash","cwd":"'"$project2"'","tool_input":{"command":"gh pr merge"}}'
uitvoer2="$(printf '%s' "$invoer2" | PATH="$fakebin2:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status2=$?

[ "$status2" -eq 0 ] || fail "S18 — post-migration format: expected pass-through (exit 0), got $status2. Output: $uitvoer2"
[ ! -e "$sentinel2" ] || fail "S18 — post-migration format: the guard called gh while the row is set to 'no'; that should stay local"

test_done
