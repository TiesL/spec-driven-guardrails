#!/usr/bin/env bash
# S623 — Revocation stops everything and does not revive (#646; A60 D7; AC7)
# Covers: F73, F74
# Public evaluator/collector/export/reader or structural seams only. Row and
# single-rule mutation map: test/fixtures/merge-risk-646.py, S623 entries.
# Actual model/executor/runtime qualification stays UNRUN (#680/#682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 -I "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 623 \
  || fail "S623 - mechanical or structural assertion failed"
test_done
