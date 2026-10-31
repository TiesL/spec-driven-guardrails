#!/usr/bin/env bash
# S472 — Invalid whole budget values refuse before check execution (#615 AC1).
# Covers: F17
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/commit-budget.sh"
budget_setup

# Include leading/trailing LF, two numeric lines, and a numeric line beside
# junk: grep's line-based match must never validate any of these strings.
if [ "${1:-}" = --preserved ]; then
  set -- 0 -3
else
  set -- $'1\n' $'\n1' $'1\n2' $'1\njunk' $'junk\n1' 0 -3 01 1000000 99999999999999999999 999999999999999999999999999999999999
fi
for bad in "$@"; do
  budget_run "$bad" success no
  budget_expect "S472 budget '$bad' refuses" status refuse
  budget_expect "S472 budget '$bad' never starts check-commit" ran no
  budget_expect "S472 budget '$bad' names invalid configuration" contains COMMIT_CHECK_BUDGET
  budget_expect "S472 budget '$bad' is never a timeout" no_timeout yes
done
budget_done
