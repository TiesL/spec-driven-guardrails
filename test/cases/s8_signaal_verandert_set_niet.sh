#!/usr/bin/env bash
# S8 — The signal does not change the outstanding set.
# Covers: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project doelproject)"
adopteer "$project"

# Given: the same project, once with substantiation gaps and once without.
met_gaten="$SANDBOX/met-gaten.txt"
openstaande_ids "$project" > "$met_gaten"

sed -i.bak 's/bij adoptie — requires substantiation tijdens PRD\/architectuur/onderbouwd voor dit project/g' \
  "$project/WORKFLOW-ADOPTION.md"
rm -f "$project/WORKFLOW-ADOPTION.md.bak"

zonder_gaten="$SANDBOX/zonder-gaten.txt"
openstaande_ids "$project" > "$zonder_gaten"

# Then: the list of outstanding IDs is identical. The signal sits alongside,
# not inside — beantwoord() is deliberately left unchanged, since that would break R9.
assert_ids_gelijk "S8" "$met_gaten" "$zonder_gaten"

# And the message itself does differ between those two states, otherwise
# this comparison tests nothing.
voor="$SANDBOX/voor.txt"; na="$SANDBOX/na.txt"
adopteer "$(vers_project tweede)" >/dev/null 2>&1 || true
tweede="$SANDBOX/tweede"
"$TEST_REPO_ROOT/pending-changes.sh" "$tweede" > "$voor" 2>/dev/null
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$na" 2>/dev/null
if diff -q "$voor" "$na" >/dev/null 2>&1; then
  fail "S8 — the output is identical with and without substantiation gaps; the signal does nothing"
fi

test_klaar
