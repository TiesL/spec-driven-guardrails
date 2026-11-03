#!/usr/bin/env bash
# S473 — A failing watchdog sleep never permits a failing check (#615 AC1).
# Covers: F17
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/commit-budget.sh"
budget_setup

budget_run 10 failure yes
budget_expect 'S473 check actually started' ran yes
budget_expect 'S473 watchdog sleep failure actually injected' sleep_failed yes
budget_expect 'S473 failing check still refuses' status refuse
budget_expect 'S473 actual check failure output retained' contains 'B615 REAL FAILURE'
budget_expect 'S473 sleep error is never elapsed timeout' no_timeout yes
budget_done
