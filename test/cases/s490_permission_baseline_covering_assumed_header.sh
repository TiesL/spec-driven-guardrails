#!/usr/bin/env bash
# S490 — permission baseline covering assumed header
# Covers: F57
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/permission-baseline-cases.py" 490 || fail "S490 — permission baseline assertion failed"
test_done
