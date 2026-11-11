#!/usr/bin/env bash
# S622 — A crash or a duplicate wake neither drops nor double-merges (#646; A60 D6/D7; AC7)
# Covers: F73
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S622 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 622 \
  || fail "S622 - mechanical or structural assertion failed"
test_done
