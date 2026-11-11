#!/usr/bin/env bash
# S616 — Completion confirms the actual merge and exact human-path revert (#646; A60 + addendum 1)
# Covers: F73
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S616 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 616 \
  || fail "S616 - mechanical or structural assertion failed"
test_done
