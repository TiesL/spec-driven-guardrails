#!/usr/bin/env bash
# S606 — Risk authority expires on every bound identity change (#646; A60 + addendum 1)
# Covers: F70, F71
# Oracle: QA-owned S606 including A60 addenda 1-3 where applicable.
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S606 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 606 \
  || fail "S606 - mechanical or structural assertion failed"
test_done
