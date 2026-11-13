#!/usr/bin/env bash
# S652 — Capture bounds apply before parsing and never accept a prefix (#646; A60 + addendum 1)
# Covers: F71
# Oracle: QA-owned S652 including A60 addenda 1-3 where applicable.
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S652 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 652 \
  || fail "S652 - mechanical or structural assertion failed"
test_done
