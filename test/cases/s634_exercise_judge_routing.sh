#!/usr/bin/env bash
# S634 — shared instruction exercise judge routing (#680; A56)
# Covers: F38, F67, F68, F69
# Offline synthetic Adapter tests; no subscription calls or behavior claims.
# Both retained judges and all consumers share the complete validation contract.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/lib.sh
. "$here/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/temporary-panel-680-tests.py" 634 || fail "S634 offline CLI assertions"
test_done
