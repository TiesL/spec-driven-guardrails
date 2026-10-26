#!/usr/bin/env bash
# templates/wait-for-ci.sh — Enforces a CI-polling cadence as a script
# instead of a prose instruction an agent could improvise around (issues
# #265, #562). The cadence follows this project's real CI: a short fixed
# interval produces a dozen-plus premature "still pending" checks before
# CI ever finishes (issue #215), and a fixed long one goes stale when CI
# gets slower or faster.
#
# Usage:
#   ./wait-for-ci.sh <pr-number>
#
# Waits 85% of the median duration (updatedAt - createdAt) of the last 10
# successful runs of the `CI` workflow without checking at all, then polls
# `gh pr checks` every 5% of it (minimum 30s) until every check reaches a
# terminal state. With fewer than 3 successful runs, or if `gh run list`
# fails or can't be parsed, it says so on stdout and falls back to 300s
# then 60s. A failed history lookup never changes the exit code. Exits 0
# if every check's terminal state counts as passing (SUCCESS, SKIPPED,
# NEUTRAL), non-zero otherwise — printing each check's name and state
# either way, so the caller doesn't have to re-query to see what failed.
#
# Requires gh; exits non-zero if it's missing or a lookup fails, rather
# than silently reporting success. This script's only job is answering
# "is it safe to ask for merge confirmation yet" — a false "yes" here is
# worse than a loud failure.
#
# Overridable via env vars: WAIT_FOR_CI_WORKFLOW (default CI),
# WAIT_FOR_CI_INITIAL_WAIT and WAIT_FOR_CI_POLL_INTERVAL (each beats the
# derived and the fallback value).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: wait-for-ci.sh <pr-number>}"

workflow="${WAIT_FOR_CI_WORKFLOW:-CI}"
history_window=10
min_history=3
fallback_initial=300
fallback_poll=60
poll_floor=30

if ! command -v gh >/dev/null 2>&1; then
  echo "wait-for-ci: gh is missing — can't check CI status." >&2
  exit 1
fi

use_fallback() {
  derived_initial="$fallback_initial"
  derived_poll="$fallback_poll"
  echo "wait-for-ci: no usable CI history ($1); using the fallback: first check after ${fallback_initial}s, then every ${fallback_poll}s."
}

# Sets derived_initial / derived_poll from the median duration of recent
# successful runs of $workflow, or the fallback values (with a notice).
# The date arithmetic runs inside gh's built-in jq, so there is no
# BSD/GNU `date` split and no external jq dependency.
derive_timing() {
  local durations rc line bad n mid i v a b median sorted
  durations="$(gh run list --workflow "$workflow" --status success --limit "$history_window" --json createdAt,updatedAt --jq '.[] | ((.updatedAt|fromdateiso8601) - (.createdAt|fromdateiso8601))' 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    use_fallback "gh run list failed"
    return
  fi

  bad=0
  while IFS= read -r line; do
    case "$line" in
      '') ;;
      *[!0-9]*) bad=1 ;;
    esac
  done <<EOF
$durations
EOF
  if [ "$bad" -eq 1 ]; then
    use_fallback "unparseable history"
    return
  fi

  sorted="$(printf '%s\n' "$durations" | sort -n)"
  # shellcheck disable=SC2086
  set -- $sorted
  n=$#
  if [ "$n" -lt "$min_history" ]; then
    use_fallback "only $n successful runs (need $min_history)"
    return
  fi

  mid=$(( (n + 1) / 2 ))
  i=0
  a=0
  b=0
  for v in "$@"; do
    i=$((i + 1))
    [ "$i" -eq "$mid" ] && a="$v"
    [ "$i" -eq $((mid + 1)) ] && b="$v"
  done
  if [ $((n % 2)) -eq 1 ]; then
    median="$a"
  else
    median=$(( (a + b) / 2 ))
  fi

  derived_initial=$(( median * 85 / 100 ))
  derived_poll=$(( median * 5 / 100 ))
  [ "$derived_poll" -ge "$poll_floor" ] || derived_poll="$poll_floor"
  echo "wait-for-ci: median of the last $n successful $workflow runs is ${median}s; first check after ${derived_initial}s, then every ${derived_poll}s."
}

# Only look up history when at least one of the two values is not overridden.
derived_initial="$fallback_initial"
derived_poll="$fallback_poll"
if [ -z "${WAIT_FOR_CI_INITIAL_WAIT:-}" ] || [ -z "${WAIT_FOR_CI_POLL_INTERVAL:-}" ]; then
  derive_timing
fi
initial_wait="${WAIT_FOR_CI_INITIAL_WAIT:-$derived_initial}"
poll_interval="${WAIT_FOR_CI_POLL_INTERVAL:-$derived_poll}"

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
