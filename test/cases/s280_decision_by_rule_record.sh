#!/usr/bin/env bash
# S280 — decision-by-rule issue record. Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s280 || fail "S280 document contract"
test_done
