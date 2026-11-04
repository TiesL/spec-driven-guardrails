#!/usr/bin/env bash
# S548 — unchanged waiver authority and core with authority limits (#647; mechanical subset only)
# Covers: F62
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/stage-selection-647.py" 548 || fail "S548 — canonical source/CLI mechanical checks; live exercise still required"
test_done
