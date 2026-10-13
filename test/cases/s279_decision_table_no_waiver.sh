#!/usr/bin/env bash
# S279 — table rows cannot waive contract rules. Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s279 || fail "S279 document contract"
test_done
