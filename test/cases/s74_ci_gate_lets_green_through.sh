#!/usr/bin/env bash
# S74 — The merge guard lets `gh pr merge` through when all checks pass.
# Covers: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project ci-green)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work

fakebin="$(fake_gh_merge_bin "pre-merge-review:done" "[{\"name\":\"check\",\"bucket\":\"pass\"}]")"

input='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
output="$(printf '%s' "$input" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S74 — expected passthrough (exit 0) for green CI, got $status. Output: $output"

test_done
