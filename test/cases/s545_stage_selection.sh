#!/usr/bin/env bash
# S545 — advance selection ordering survives history changes (#647; mechanical subset only)
# Covers: F62
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/stage-selection-647.py" 545 || fail "S545 — canonical source/CLI mechanical checks; live exercise still required"
test_done
