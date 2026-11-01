#!/usr/bin/env bash
# S491 — permission baseline reject verified header
# Covers: F57
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/permission-baseline-cases.py" 491 || fail "S491 — permission baseline assertion failed"
test_done
