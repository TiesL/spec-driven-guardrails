#!/usr/bin/env bash
# S15 — Merge without a review marker is blocked.
# Covers: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project zonder-marker)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_merge_bin "" "")"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S15 — expected block (exit 2), got $status. Output: $uitvoer"
assert_contains "S15" "pre-merge-review" "$uitvoer"

test_klaar
