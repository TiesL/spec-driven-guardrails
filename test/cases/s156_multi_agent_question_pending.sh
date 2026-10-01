#!/usr/bin/env bash
# S156 — process-multi-agent-roles is asked, never seeded.
# Covers: F37
#
# Issue #369, AC2. Seams: adopt.sh (what it seeds into WORKFLOW-ADOPTION.md)
# and pending-changes.sh (what it reports as pending), for a fresh project
# and for an already-adopted project that has no row for the new id.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"

# --- Fresh adoption --------------------------------------------------------
# Given: a fresh project, right after adoption.
project="$(fresh_project fresh)"
adopt "$project"

# Then: adopt.sh did not seed a row for it (a `question` default).
seeded_ids "$project" > "$SANDBOX/fresh-seeded.txt"
if grep -qx "$id" "$SANDBOX/fresh-seeded.txt"; then
  fail "S156 — adopt.sh seeded a row for $id; a question-default entry must stay unanswered"
fi

# And: pending-changes.sh lists it as pending.
pending_ids "$project" > "$SANDBOX/fresh-pending.txt"
if ! grep -qx "$id" "$SANDBOX/fresh-pending.txt"; then
  fail "S156 — pending-changes.sh does not list $id as pending after a fresh adoption"
fi

# --- An already-adopted project ---------------------------------------------
# Given: a copy of a frozen, already-adopted project with no row for the id.
fixture="$TEST_REPO_ROOT/test/fixtures/baseline/tennis-invoicing"
adopted="$SANDBOX/adopted"
cp -R "$fixture" "$adopted"
seeded_ids "$adopted" > "$SANDBOX/adopted-seeded.txt"
if grep -qx "$id" "$SANDBOX/adopted-seeded.txt"; then
  fail "S156 — fixture precondition broken: the adopted project already answers $id"
fi

# When / Then: pending-changes.sh lists it as pending there too.
pending_ids "$adopted" > "$SANDBOX/adopted-pending.txt"
if ! grep -qx "$id" "$SANDBOX/adopted-pending.txt"; then
  fail "S156 — pending-changes.sh does not list $id as pending for an adopted project without a row"
fi

test_done
