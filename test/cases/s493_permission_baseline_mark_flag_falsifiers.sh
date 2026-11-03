#!/usr/bin/env bash
# S493 — permission baseline mark flag falsifiers
# Covers: F57
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/permission-baseline-cases.py" 493 || fail "S493 — permission baseline assertion failed"
test_done
