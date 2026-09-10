#!/usr/bin/env bash
# S73 — The merge guard blocks `gh pr merge` when CI is not green.
# Dekt: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project ci-rood)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_merge_bin "pre-merge-review:done" "[{\"name\":\"check\",\"bucket\":\"fail\"}]")"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S73 — expected block (exit 2) for failing CI, got $status. Output: $uitvoer"
assert_contains "S73 — the message names the failing check" "check: fail" "$uitvoer"

test_klaar
