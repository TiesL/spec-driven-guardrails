#!/usr/bin/env bash
# S289 — SKILL.md defines Fix cost and trivial once (#488). Covers: F38, F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s289 || fail "S289 document contract"
test_done
