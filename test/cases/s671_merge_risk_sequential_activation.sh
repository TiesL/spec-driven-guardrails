#!/usr/bin/env bash
# S671 — A tiny activating PR is judged with dormant behavior already in B (#646; A60 + addendum 1)
# Covers: F71, F72, F74
# Oracle: QA-owned S671 including A60 addenda 1-3 where applicable.
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S671 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 671 \
  || fail "S671 - mechanical or structural assertion failed"
test_done
