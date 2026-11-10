#!/usr/bin/env bash
# S633 — shared instruction exercise schedule status (#680; A56)
# Covers: F67, F68, F69
# Offline synthetic Adapter tests; no subscription calls or behavior claims.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/lib.sh
. "$here/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/temporary-panel-680-tests.py" 633 || fail "S633 offline CLI assertions"
test_done
