#!/usr/bin/env bash
# S16 — Merge with a review marker goes through.
# Covers: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project with-marker)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work

fakebin="$(fake_gh_merge_bin "pre-merge-review:done" "")"

input='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
output="$(printf '%s' "$input" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S16 — expected pass-through (exit 0), got $status. Output: $output"

test_done
