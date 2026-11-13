#!/usr/bin/env bash
# S613 — Finite hard stops and procedural vetoes replace the old class (#646; A60 + addendum 1)
# Covers: F72
# Oracle: QA-owned S613 including A60 addenda 1-3 where applicable.
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S613 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 613 \
  || fail "S613 - mechanical or structural assertion failed"
test_done
