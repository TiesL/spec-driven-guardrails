#!/usr/bin/env bash
# S624 — Live exercises for the model-dependent parts (#646)
# Covers: F70, F71, F72, F73, F74
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S624
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
BEH="$TEST_REPO_ROOT/test/behavior/merge-risk-scenarios.md"
# S624 is the live exercise for #682: UNRUN by design (subscription usage), never invoked here.
[ -f "$BEH" ] || fail "S624 - test/behavior/merge-risk-scenarios.md missing (stub marking the exercises UNRUN)"
grep -q 'UNRUN' "$BEH" 2>/dev/null || fail "S624 - merge-risk-scenarios.md must be marked UNRUN until #682 runs it"
test_done
