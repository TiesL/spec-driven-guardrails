#!/usr/bin/env bash
# S283 — injected decision-table budget. Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s283 || fail "S283 document contract"
test_done
