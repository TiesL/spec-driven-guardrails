#!/usr/bin/env bash
# templates/wait-for-ci.sh — Enforces the 5-minutes-then-1-minute CI
# polling cadence as a script instead of a prose instruction an agent
# could improvise around (issue #265). This repo's own CI runs cluster
# at 5.5-8 minutes (issue #215); a short fixed interval produces a
# dozen-plus premature "still pending" checks before CI ever finishes.
#
# Usage:
#   ./wait-for-ci.sh <pr-number>
#
# Waits 5 minutes without checking at all, then polls `gh pr checks`
# every 1 minute until every check reaches a terminal state. Exits 0 if
# every check's terminal state counts as passing (SUCCESS, SKIPPED,
# NEUTRAL), non-zero otherwise — printing each check's name and state
# either way, so the caller doesn't have to re-query to see what failed.
#
# Requires gh; exits non-zero if it's missing or a lookup fails, rather
# than silently reporting success. This script's only job is answering
# "is it safe to ask for merge confirmation yet" — a false "yes" here is
# worse than a loud failure.
#
# Overridable via env vars for testing: WAIT_FOR_CI_INITIAL_WAIT (default
# 300s), WAIT_FOR_CI_POLL_INTERVAL (default 60s).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: wait-for-ci.sh <pr-number>}"
initial_wait="${WAIT_FOR_CI_INITIAL_WAIT:-300}"
poll_interval="${WAIT_FOR_CI_POLL_INTERVAL:-60}"

if ! command -v gh >/dev/null 2>&1; then
  echo "wait-for-ci: gh is missing — can't check CI status." >&2
  exit 1
fi

echo "wait-for-ci: waiting ${initial_wait}s before the first check on PR #$pr_number..."
sleep "$initial_wait"

# Non-terminal states: still running, nothing to report yet.
is_pending() {
  case "$1" in
    PENDING|QUEUED|IN_PROGRESS|REQUESTED|WAITING) return 0 ;;
    *) return 1 ;;
  esac
}

# Terminal states that count as passing. Anything else terminal (FAILURE,
# ERROR, CANCELLED, TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE, STALE, ...)
# counts as a failure.
is_passing() {
  case "$1" in
    SUCCESS|SKIPPED|NEUTRAL) return 0 ;;
    *) return 1 ;;
  esac
}

# One query per poll, name+state together — not a separate --json state
# pass for the pending-loop and a second --json name,state pass afterward
# just to print names: two queries invite exactly the drift a single
# source of truth avoids, and cost an avoidable extra network round trip
# each time. Found during PR #279's pre-merge-review.
while true; do
  detail="$(gh pr checks "$pr_number" --json name,state --jq '.[] | "\(.name)\t\(.state)"' 2>&1)"
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "wait-for-ci: couldn't consult PR #$pr_number's checks: $detail" >&2
    exit 1
  fi

  still_pending=0
  while IFS="$(printf '\t')" read -r _name state; do
    [ -n "$state" ] || continue
    if is_pending "$state"; then
      still_pending=1
      break
    fi
  done <<EOF
$detail
EOF

  [ "$still_pending" -eq 1 ] || break
  sleep "$poll_interval"
done

# A PR with zero checks at all isn't "all checks passed" — there is
# nothing to have passed. Reported as inconclusive, not silent success:
# the whole point of this script is answering whether it's safe to ask
# for merge confirmation, and "no checks ran" doesn't answer that. Found
# during PR #279's pre-merge-review (untested edge case in round 1).
if [ -z "$detail" ]; then
  echo "wait-for-ci: PR #$pr_number has no checks at all — nothing to wait for or confirm." >&2
  exit 1
fi

while IFS="$(printf '\t')" read -r name state; do
  [ -n "$name" ] || continue
  echo "$name: $state"
done <<EOF
$detail
EOF

all_pass=1
while IFS="$(printf '\t')" read -r _name state; do
  [ -n "$state" ] || continue
  is_passing "$state" || all_pass=0
done <<EOF
$detail
EOF

if [ "$all_pass" -eq 1 ]; then
  echo "wait-for-ci: all checks passed."
  exit 0
fi
echo "wait-for-ci: one or more checks did not pass." >&2
exit 1
