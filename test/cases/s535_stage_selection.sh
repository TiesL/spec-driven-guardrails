#!/usr/bin/env bash
# S535 — complete separate panel record (#647; mechanical subset only)
# Covers: F62
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/stage-selection-647.py" 535 || fail "S535 — canonical source/CLI mechanical checks; live exercise still required"
test_done
