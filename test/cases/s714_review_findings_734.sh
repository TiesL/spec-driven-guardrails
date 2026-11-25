#!/usr/bin/env bash
# S714 — #734 review finding regression
# Covers: F38
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/review-findings-734.py" 714 || fail "S714 review finding"
test_done
