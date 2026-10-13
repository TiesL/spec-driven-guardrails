#!/usr/bin/env bash
# S278 — never-list in the injected decision table. Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s278 || fail "S278 document contract"
test_done
