#!/usr/bin/env bash
# S717 — #734 review finding regression
# Covers: F70
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/review-findings-734.py" 717 || fail "S717 review finding"
test_done
