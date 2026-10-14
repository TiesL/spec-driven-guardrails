#!/usr/bin/env bash
# S288 — ORCHESTRATOR.md low-finding row states the trivial-fix rule (#488). Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/decision-table-415.py" "$TEST_REPO_ROOT" s288 || fail "S288 document contract"
test_done
