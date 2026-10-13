#!/usr/bin/env bash
# S277 — seeded rows in the injected decision table. Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s277 || fail "S277 document contract"
test_done
