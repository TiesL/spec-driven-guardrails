#!/usr/bin/env bash
# S631 — shared instruction exercise evidence retention (#680; A56)
# Covers: F67, F68
# Offline synthetic Adapter tests; no subscription calls or behavior claims.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/lib.sh
. "$here/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/temporary-panel-680-tests.py" 631 || fail "S631 offline CLI assertions"
test_done
