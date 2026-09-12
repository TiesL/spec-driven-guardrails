#!/usr/bin/env bash
# S8 — The signal does not change the outstanding set.
# Covers: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project target-project)"
adopt "$project"

# Given: the same project, once with substantiation gaps and once without.
with_gaps="$SANDBOX/met-gaten.txt"
pending_ids "$project" > "$with_gaps"

sed -i.bak 's/at adoption — requires substantiation during PRD\/architecture/onderbouwd before dit project/g' \
  "$project/WORKFLOW-ADOPTION.md"
rm -f "$project/WORKFLOW-ADOPTION.md.bak"

without_gaps="$SANDBOX/zonder-gaten.txt"
pending_ids "$project" > "$without_gaps"

# Then: the list of outstanding IDs is identical. The signal sits alongside,
# not inside — beantwoord() is deliberately left unchanged, since that would break R9.
assert_ids_equal "S8" "$with_gaps" "$without_gaps"

# And the message itself does differ between those two states, otherwise
# this comparison tests nothing.
before="$SANDBOX/before.txt"; na="$SANDBOX/na.txt"
adopt "$(fresh_project second)" >/dev/null 2>&1 || true
second="$SANDBOX/second"
"$TEST_REPO_ROOT/pending-changes.sh" "$second" > "$before" 2>/dev/null
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$na" 2>/dev/null
if diff -q "$before" "$na" >/dev/null 2>&1; then
  fail "S8 — the output is identical with and without substantiation gaps; the signal does nothing"
fi

test_done
