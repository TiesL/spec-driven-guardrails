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

output="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>/dev/null)"

assert_contains "S54 — the message mentions main" "main" "$output"
assert_contains "S54 — the message suggests git checkout -b" "git checkout -b" "$output"

test_done
