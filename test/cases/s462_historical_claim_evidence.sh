#!/usr/bin/env bash
# S462 — historical claim evidence
# Covers: F59
# A49 loaded-text seam; per-obligation positive/deletion mutation controls.
# This pin does not establish live role obedience (shared behavior run required).
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/oracle-contract-pins.py" 462 || fail "S462 — loaded contract fails A49 obligations"
test_done
