#!/usr/bin/env bash
# S589 — temporary-decision panel (#645; mechanical subset only)
# Covers: F67
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/temporary-panel-645.py" 589 || fail "S589 mechanical checks; behavior exercises remain unrun"
test_done
