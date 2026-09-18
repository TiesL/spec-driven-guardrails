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

pr_json="$(gh pr view "$pr_number" --json comments,closingIssuesReferences 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number (no network or no access) and is skipping the model-record check." >&2
  echo "$pr_json" >&2
  exit 0
fi

pr_comments="$(printf '%s' "$pr_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for c in data.get("comments", []):
    print(c.get("body", ""))
print("---ISSUES---")
for ref in data.get("closingIssuesReferences", []):
    n = ref.get("number")
    if n is not None:
        print(n)
' 2>/dev/null)"
parse_status=$?
if [ "$parse_status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't interpret gh's output and is skipping the model-record check." >&2
  exit 0
fi

body_part="$(printf '%s\n' "$pr_comments" | sed -n '1,/^---ISSUES---$/p' | sed '$d')"
issue_numbers="$(printf '%s\n' "$pr_comments" | sed -n '/^---ISSUES---$/,$p' | tail -n +2)"

all_text="$body_part"
if [ -n "$issue_numbers" ]; then
  while IFS= read -r issue_num; do
    [ -n "$issue_num" ] || continue
    issue_body="$(gh issue view "$issue_num" --json comments --jq '.comments[].body' 2>/dev/null)"
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
