#!/usr/bin/env bash
# skills/pre-merge-review/adoption-postcondition-gate.sh — #239 AC1: makes a
# "yes" answer in WORKFLOW-ADOPTION.md verifiable instead of self-asserted.
#
# Usage:
#   adoption-postcondition-gate.sh <project_dir>
#
# Deliberately scoped to the two rows #238's audit actually found broken —
# not a generic per-row postcondition framework. traceability-link-1 and
# ci-gate-on-merge were both answered "yes" in portfolio-mgt-agents while
# structurally unable to hold: no check-traceability.sh existed there, and
# no CI config existed to invoke `check` at all.
#
# check-traceability.sh (link 1) and its wiring into a project's own
# `check` share the same limitation this script has: nothing forces a
# project to actually call either one. That's why this runs from
# pre-merge-review (see that skill's "Adoption postcondition gate"
# section), not from the adopted project's own optional `check` — a
# project that never wires this in also wouldn't run a self-check that
# depends on being wired in.
#
# Filesystem-only, no gh/network — always runs, nothing to fail open on.
# Output on stdout: one line per broken postcondition:
#   "<row-id>: yes, but <what's missing> (adoption postcondition)"
#
# No `eval`. WORKFLOW-ADOPTION.md's Notes column isn't under this script's
# control. Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

project_dir="${1:?usage: adoption-postcondition-gate.sh <project_dir>}"
answers="$project_dir/WORKFLOW-ADOPTION.md"

[ -f "$answers" ] || exit 0

# A row's answer starts with "yes" if the Answer column (second table cell)
# does — "yes", "yes — requires substantiation", etc. all count; "no" and
# "no — not yet" (see #239 AC3) do not. Matches on the row's own line only,
# same "only the field counts" discipline as check-traceability.sh/
# scenario-gate.sh — no matching on prose that merely mentions a row id.
row_answered_yes() {
  local id="$1" line
  line="$(grep -E "^\| *$id *\|" "$answers")"
  # <<< here-string, not a piped producer | grep -q: SIGPIPE/pipefail race,
  # see issue #218 and check-no-sigpipe-race.sh.
  grep -qE '^\| *[^|]+\| *yes' <<<"$line"
}

if row_answered_yes "traceability-link-1"; then
  if [ ! -f "$project_dir/check-traceability.sh" ]; then
    echo "traceability-link-1: yes, but check-traceability.sh does not exist in this project (adoption postcondition)"
  elif ! grep -q "check-traceability.sh" "$project_dir/check" 2>/dev/null; then
    echo "traceability-link-1: yes, but this project's own check script never calls check-traceability.sh (adoption postcondition)"
  fi
fi

if row_answered_yes "ci-gate-on-merge"; then
  ci_found=0
  ci_calls_check=0
  # Process substitution, not a piped while-read: a pipe would run the loop
  # in a subshell, and ci_found/ci_calls_check set there would vanish the
  # moment the loop ends — same class of mistake S-series tests elsewhere
  # in this repo guard against.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    ci_found=1
    grep -q "check" "$f" 2>/dev/null && ci_calls_check=1
  done < <(find "$project_dir/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)

  if [ "$ci_found" -eq 0 ]; then
    echo "ci-gate-on-merge: yes, but no CI workflow exists under .github/workflows/ (adoption postcondition)"
  elif [ "$ci_calls_check" -eq 0 ]; then
    echo "ci-gate-on-merge: yes, but no CI workflow appears to invoke check (adoption postcondition)"
  fi
fi

exit 0
