#!/usr/bin/env bash
# skills/pre-merge-review/model-record-gate.sh — #241 AC1: makes
# process-model-choice mechanically checkable instead of resting on an
# agent remembering to follow the model-choice skill's prose instruction.
#
# Usage:
#   model-record-gate.sh <pr-number>
#
# Checks that all five pipeline stages (Discovery, Planning, Test,
# Implementation, Review) have at least one machine-readable
#   <!-- model-record: stage=<Stage> model="..." effort="..." -->
# marker, searched across both the PR's own comments and the comments of
# every issue it closes (Discovery is typically recorded on the issue,
# the other four on the PR — but this searches both for either, since
# model-choice's own "single session" note allows one session to do every
# stage and record all of them wherever it's writing at the time).
#
# Found via #238 (portfolio-mgt-agents): only the Review stage ever
# recorded a model in practice — Discovery/Planning/Test/Implementation
# never did, and nothing made that visible before this gate.
#
# Fail-open without gh or network: warn, don't block — same ground rule
# as every other gate here (scenario-gate.sh, check-pr-issue-link.sh).
#
# Output on stdout: one line per missing stage:
#   "model-record: no record found for stage <Stage> (missing model-choice marker)"
#
# No `eval`. PR/issue comment text isn't under this script's control.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: model-record-gate.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: model-record-gate can't find gh and is skipping the model-record check." >&2
  exit 0
fi

body_part="$(gh pr view "$pr_number" --json comments --jq '.comments[].body' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's comments (no network or no access) and is skipping the model-record check." >&2
  echo "$body_part" >&2
  exit 0
fi

issue_numbers="$(gh pr view "$pr_number" --json closingIssuesReferences --jq '.closingIssuesReferences[].number' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's closing issues (no network or no access) and is skipping the model-record check." >&2
  echo "$issue_numbers" >&2
  exit 0
fi

all_text="$body_part"
if [ -n "$issue_numbers" ]; then
  while IFS= read -r issue_num; do
    [ -n "$issue_num" ] || continue
    issue_body="$(gh issue view "$issue_num" --json comments --jq '.comments[].body' 2>&1)"
    issue_status=$?
    if [ "$issue_status" -ne 0 ]; then
      # Found during PR #249's pre-merge-review (round 2): silently
      # swallowing this would misreport "no Discovery record" as if the
      # stage were genuinely missing, rather than "couldn't check" — a
      # transient failure here must warn, same as every other gh call in
      # this script, not degrade to a false negative.
      echo "warning: model-record-gate couldn't consult issue #$issue_num (no network or no access) and is skipping its comments." >&2
      echo "$issue_body" >&2
      continue
    fi
    all_text="$all_text
$issue_body"
  done <<<"$issue_numbers"
fi

for stage in Discovery Planning Test Implementation Review; do
  # <<< here-string, not a piped producer | grep -q: SIGPIPE/pipefail
  # race, see issue #218 and check-no-sigpipe-race.sh.
  if ! grep -qE "model-record:[[:space:]]*stage=$stage\\b" <<<"$all_text"; then
    echo "model-record: no record found for stage $stage (missing model-choice marker)"
  fi
done
