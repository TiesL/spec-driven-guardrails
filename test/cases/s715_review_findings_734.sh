#!/usr/bin/env bash
# S715 — #734 review finding regression
# Covers: F71, F72
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/review-findings-734.py" 715 || fail "S715 review finding"
test_done
