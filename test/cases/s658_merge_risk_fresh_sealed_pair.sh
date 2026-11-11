#!/usr/bin/env bash
# S658 — Two cross-vendor results are independent, sealed and non-reused (#646; A60 + addendum 1)
# Covers: F71
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S658 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 658 \
  || fail "S658 - mechanical or structural assertion failed"
test_done
