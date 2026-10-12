#!/usr/bin/env bash
# S281 — pushback once before human decision. Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s281 || fail "S281 document contract"
test_done
