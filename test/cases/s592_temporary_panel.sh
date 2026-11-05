#!/usr/bin/env bash
# S592 — temporary-decision panel (#645; mechanical subset only)
# Covers: F69
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/temporary-panel-645.py" 592 || fail "S592 mechanical checks; behavior exercises remain unrun"
test_done
