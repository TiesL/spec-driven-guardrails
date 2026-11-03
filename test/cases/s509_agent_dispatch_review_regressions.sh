#!/usr/bin/env bash
# S509 — Outside wrapper comments and hostile PR whitespace preserve checks (#618)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/dispatch-regressions-618.py" "$TEST_REPO_ROOT" "$SANDBOX" || fail "S509 — review regressions failed"
test_done
