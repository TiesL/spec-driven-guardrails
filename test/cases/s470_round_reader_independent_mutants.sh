#!/usr/bin/env bash
# S470 — independent round-reader mutants each fail their targeted assertion.
# Covers: F42
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/round-reader-mutations.py" "$TEST_REPO_ROOT" "$SANDBOX" \
  || fail "S470 — independent controls/mutations or redundant grep requirement failed"
test_done
