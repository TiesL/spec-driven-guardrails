#!/usr/bin/env bash
# S54 — Session start reports that `main` is checked out.
# Covers: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project on-main)"
git -C "$project" commit -q --allow-empty -m start

output="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>"$SANDBOX/stderr")"; status=$?

assert_contains "S54 — the message mentions main" "main" "$output"
assert_contains "S54 — issue precedes WIP work" "Create the issue first, then work on WIP:" "$output"
assert_contains "S54 — the message suggests a WIP checkout" "git checkout -b wip/<issue-number>-<name>" "$output"
if grep -qE 'checkout -b (feature|fix)/' <<<"$output"; then
  fail "S54 — startup still suggests a publication-branch checkout"
fi
[ "$status" -eq 0 ] || fail "S54 — startup must exit 0"
[ ! -s "$SANDBOX/stderr" ] || fail "S54 — startup must leave stderr empty"

test_done
