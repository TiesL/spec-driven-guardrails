#!/usr/bin/env bash
# S64 — The merge-guard escape hatch only disables the merge guard.
# Dekt: F8
#
# Found in pre-merge-review on PR #70: CLAUDE_WORKFLOW_MERGE_GUARD_UIT=1 did a
# blanket `return 0` for the entire segment, and thereby also let through
# destructive git commands with the same var prefix.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project uitweg-scope)"
git -C "$project" commit -q --allow-empty -m start

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"CLAUDE_WORKFLOW_MERGE_GUARD_UIT=1 git reset --hard"}}'
uitvoer="$(printf '%s' "$invoer" | "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S64 — the merge-guard escape hatch let 'git reset --hard' through (exit $status). Output: $uitvoer"
assert_contains "S64 — the block mentions reset --hard" "reset --hard" "$uitvoer"

test_klaar
