#!/usr/bin/env bash
# S36 — An ID in the explanation does not count as an answer.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project with-notes)"
adopt "$project"

# test-integration has `Default: question` and is therefore never seeded: it is
# still open after a fresh adoption. That's the control value.
before="$SANDBOX/before.txt"
pending_ids "$project" > "$before"
grep -qx 'test-integration' "$before" || {
  fail "S36 — test-integration was not open after fresh adoption; the setup is broken"
  test_done
}

# Given: the ID appears in the free-text explanation of another row.
printf '| process-prd | yes | 2026-01-01 | no test-integration agreed yet |\n' \
  >> "$project/WORKFLOW-ADOPTION.md"

# When/Then: the change is still open - only the ID column counts.
after="$SANDBOX/after.txt"
pending_ids "$project" > "$after"

if ! grep -qx 'test-integration' "$after"; then
  fail "S36 — test-integration disappeared because of a mention in the explanation"
fi

test_done
