#!/usr/bin/env bash
# S498 — blank wording pins (#616).
# Covers: F38
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/override-616.py" 498 || fail "S498 — #616 witness"
test_done
