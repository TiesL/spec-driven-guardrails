#!/usr/bin/env bash
# S82 — A fresh WORKFLOW-ADOPTION.md names the correct repo name.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: an empty git project without package.json.
project="$(vers_project leeg)"

# When: adopt.sh is run.
adopteer "$project"

tabel="$project/WORKFLOW-ADOPTION.md"
if [ ! -f "$tabel" ]; then
  fail "S82 — adopt.sh did not create a WORKFLOW-ADOPTION.md"
  test_klaar
fi

# Then: the header refers to the current name, not the name from before
# the W32 rename (#56).
if grep -q "claude-workflow" "$tabel"; then
  fail "S82 — WORKFLOW-ADOPTION.md still refers to the old name claude-workflow"
fi
grep -q "spec-driven-guardrails" "$tabel" \
  || fail "S82 — WORKFLOW-ADOPTION.md does not mention spec-driven-guardrails"

test_klaar
