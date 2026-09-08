#!/usr/bin/env bash
# S16 — Merge mét review-marker gaat door.
# Dekt: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project met-marker)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_merge_bin "pre-merge-review:done" "")"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S16 — verwacht doorgang (exit 0), kreeg $status. Uitvoer: $uitvoer"

test_klaar
