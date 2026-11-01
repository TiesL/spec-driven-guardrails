#!/usr/bin/env bash
# S480 — S285 rejects false completeness, conflicting counts and numeric prefixes (#613).
# Covers: F15
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -B "$TEST_REPO_ROOT/test/fixtures/s480_release_note_oracle_mutations.py" "$TEST_REPO_ROOT" || fail 'S480 — S285 mutation checks failed'
test_done
