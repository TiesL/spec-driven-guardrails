#!/usr/bin/env bash
# S542 — split skip escalates while retained work stays (#647; mechanical subset only)
# Covers: F61
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/stage-selection-647.py" 542 || fail "S542 — canonical source/CLI mechanical checks; live exercise still required"
test_done
