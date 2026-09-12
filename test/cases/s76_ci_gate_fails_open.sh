#!/usr/bin/env bash
# S76 — The CI gate fails open when the CI query itself fails.
# Covers: F8
#
# The review marker is present (so the first check passes); the CI check
# itself fails (no network, gh error, whatever). Same ground rule as
# everywhere in this guard: the check is never the command that gets stuck.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project ci-query-fails)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"bevindingen\\n<!-- pre-merge-review:done -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    exit 1 ;;
esac
exit 1
')"

input='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
output="$(printf '%s' "$input" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S76 — expected passthrough (exit 0) when the CI query fails, got $status. Output: $output"
assert_contains "S76 — loud warning about the skipped CI check" "warning" "$output"

test_done
