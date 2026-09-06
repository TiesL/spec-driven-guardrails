#!/usr/bin/env bash
# S64 — De merge-guard-uitweg schakelt alleen de merge-guard uit.
# Dekt: F8
#
# Gevonden in pre-merge-review op PR #70: CLAUDE_WORKFLOW_MERGE_GUARD_UIT=1
# deed een blanco `return 0` voor het hele segment, en liet daarmee ook
# destructieve git-commando's met dezelfde var-prefix door.

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

[ "$status" -eq 2 ] || fail "S64 — de merge-guard-uitweg liet 'git reset --hard' door (exit $status). Uitvoer: $uitvoer"
assert_contains "S64 — de blokkade noemt reset --hard" "reset --hard" "$uitvoer"

test_klaar
