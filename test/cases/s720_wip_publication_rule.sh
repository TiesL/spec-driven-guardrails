#!/usr/bin/env bash
# S720 — #706 loaded instruction obligations and deletion controls.
# Covers: F76
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/wip-promotion-706.py" 720 || fail "S720 — #706 instruction obligations missing"
# The replacement must remove the old automatic-push target instructions,
# not merely append a contradictory WIP paragraph.
if grep -qF 'Commit logical steps on the feature branch.' "$TEST_REPO_ROOT/policy/WORKFLOW.md"; then
  fail "S720/old-commit-target — canonical workflow still sends checkpoint commits to feature"
fi
if grep -qF 'Push regularly to `origin/<branch>`' "$TEST_REPO_ROOT/policy/WORKFLOW.md"; then
  fail "S720/old-push-target — canonical workflow still gives an undifferentiated push instruction"
fi
test_done
