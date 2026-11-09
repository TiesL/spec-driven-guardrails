#!/usr/bin/env bash
# S606 — Votes expire when the head changes, including update-branch (#646)
# Covers: F70
#
# Mechanical subset only, judged through the verifier's command-line contract
# (first stdout line, reason codes, exit status, fake gh call log). The rows,
# the rule-to-row mutation map and every mutation check live in the S606 block
# of test/fixtures/merge-risk-646.py; model obedience is S624 (UNRUN, #682).
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 "$TEST_REPO_ROOT/test/fixtures/merge-risk-646.py" 606 \
  || fail "S606 - mechanical rows or mutation checks failed (FAIL lines above)"
test_done
