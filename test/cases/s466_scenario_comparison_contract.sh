#!/usr/bin/env bash
# S466 — scenario comparison contract
# Covers: F60
# A49 loaded-text seam; per-obligation positive/deletion mutation controls.
# This pin does not establish live role obedience (shared behavior run required).
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/oracle-contract-pins.py" 466 || fail "S466 — loaded contract fails A49 obligations"
test_done
