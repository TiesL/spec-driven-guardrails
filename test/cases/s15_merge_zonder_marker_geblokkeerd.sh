#!/usr/bin/env bash
# S15 — Merge zonder review-marker wordt geblokkeerd.
# Dekt: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project zonder-marker)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    echo "{\"comments\":[{\"body\":\"geen marker hier\"}]}"
    exit 0 ;;
esac
exit 1
')"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S15 — verwacht blokkade (exit 2), kreeg $status. Uitvoer: $uitvoer"
assert_contains "S15" "pre-merge-review" "$uitvoer"

test_klaar
