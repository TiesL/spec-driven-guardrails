#!/usr/bin/env bash
# S650 — The small verdict schema has closed fields, types and enumerations (#646; A60 + addendum 1)
# Covers: F71
# Oracle: QA-owned S650 including A60 addenda 1-3 where applicable.
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S650 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 650 \
  || fail "S650 - mechanical or structural assertion failed"
test_done
