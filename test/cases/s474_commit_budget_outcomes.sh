#!/usr/bin/env bash
# S474 — Valid completion, real failure and elapsed timeout retain outcomes (#615 AC1).
# Covers: F17
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/commit-budget.sh"
budget_setup

# Upper accepted boundary must not accidentally become an invalid budget.
for good in 1 30 999999; do
  budget_run "$good" success no
  budget_expect "S474 budget $good completes successfully" status allow
  budget_expect "S474 budget $good runs the check" ran yes
  budget_expect "S474 budget $good completion is no timeout" no_timeout yes
done
budget_run 10 failure no
budget_expect 'S474 real failure refuses' status refuse
budget_expect 'S474 real failure ran' ran yes
budget_expect 'S474 real failure output is visible' contains 'B615 REAL FAILURE'
budget_expect 'S474 real failure is no timeout' no_timeout yes
budget_run 1 timeout no
budget_expect 'S474 elapsed timeout allows' status allow
budget_expect 'S474 timed-out check started' ran yes
budget_expect 'S474 elapsed timeout is identified' contains exceeded
budget_expect 'S474 elapsed timeout points to CI' contains CI
budget_done
