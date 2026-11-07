#!/usr/bin/env bash
# S590 — temporary-decision panel (#645; mechanical subset only)
# Covers: F68
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/temporary-panel-645.py" 590 || fail "S590 mechanical checks; behavior exercises remain unrun"
test_done
