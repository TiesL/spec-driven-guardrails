#!/usr/bin/env bash
# S499 — test witnesses (#616).
# Covers: F56
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/override-616.py" 499 || fail "S499 — #616 witness"
test_done
