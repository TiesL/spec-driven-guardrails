#!/usr/bin/env bash
# S537 — orchestrator fresh Review and independent scrutiny (#647; mechanical subset only)
# Covers: F61
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/stage-selection-647.py" 537 || fail "S537 — canonical source/CLI mechanical checks; live exercise still required"
test_done
