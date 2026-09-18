#!/usr/bin/env bash
# skills/pre-merge-review/issue-structure-gate.sh — #242: the missing 4th
# traceability link (issue -> acceptance-criteria structure). Link 1
# (PRD -> scenario) is check-traceability.sh; link 2 (scenario -> issue)
# is scenario-gate.sh; link 3 (PR -> issue) is check-pr-issue-link.sh.
# None of them check the issue itself has the structure those other links
# assume exists.
#
# Usage:
#   issue-structure-gate.sh <pr-number>
#
# For every issue the PR closes:
#   - a Work item issue (no "epic" label) must have at least one
#     `### AC<n>` heading and a `**Covers:**` field;
#   - an Epic issue (labeled "epic") must have at least one real
#     `- [ ] #<n>` / `- [x] #<n>` entry under its Work items list, not the
#     unfilled template placeholder (`- [ ] #`).
#
# Found via #238 (portfolio-mgt-agents): zero issues had any of this
# structure — no epic issue, no AC<n>, no Covers: field — and nothing
# checked for it.
#
# Fail-open without gh or network: warn, don't block — same ground rule
# as every other gate here.
#
# Output on stdout: one line per structural gap:
#   "issue-structure: #<n> is a work item with no AC<n> heading (link 4)"
#   "issue-structure: #<n> is a work item with no Covers: field (link 4)"
#   "issue-structure: #<n> is an epic with no linked work items (link 4)"
#
# No `eval`. Issue body text isn't under this script's control.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: issue-structure-gate.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: issue-structure-gate can't find gh and is skipping link 4." >&2
  exit 0
fi

issue_numbers="$(gh pr view "$pr_number" --json closingIssuesReferences --jq '.closingIssuesReferences[].number' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: issue-structure-gate couldn't consult PR #$pr_number's closing issues (no network or no access) and is skipping link 4." >&2
  echo "$issue_numbers" >&2
  exit 0
fi

[ -n "$issue_numbers" ] || exit 0

while IFS= read -r issue_num; do
  [ -n "$issue_num" ] || continue

  labels="$(gh issue view "$issue_num" --json labels --jq '.labels[].name' 2>&1)"
  label_status=$?
  if [ "$label_status" -ne 0 ]; then
    echo "warning: issue-structure-gate couldn't consult issue #$issue_num's labels (no network or no access) and is skipping it." >&2
    echo "$labels" >&2
    continue
  fi

  body="$(gh issue view "$issue_num" --json body --jq '.body' 2>&1)"
  body_status=$?
  if [ "$body_status" -ne 0 ]; then
    echo "warning: issue-structure-gate couldn't consult issue #$issue_num's body (no network or no access) and is skipping it." >&2
    echo "$body" >&2
    continue
  fi

  is_epic=0
  # <<< here-string, not a piped producer | grep -q: SIGPIPE/pipefail
  # race, see issue #218 and check-no-sigpipe-race.sh.
  grep -qxF "epic" <<<"$labels" && is_epic=1

  if [ "$is_epic" -eq 1 ]; then
    if ! grep -qE '^- \[[ x]\] #[0-9]+' <<<"$body"; then
      echo "issue-structure: #$issue_num is an epic with no linked work items (link 4)"
    fi
  else
    if ! grep -qE '^### AC[0-9]+' <<<"$body"; then
      echo "issue-structure: #$issue_num is a work item with no AC<n> heading (link 4)"
    fi
    # W42/#114: also accept the pre-migration **Dekt:** field, same
    # permanent exception scenario-gate.sh already carries — an
    # historical issue's own field isn't rewritten for this migration.
    # Found during PR #251's pre-merge-review: this and scenario-gate.sh
    # would otherwise disagree about the same issue.
    if ! grep -qE '^\*\*(Covers|Dekt):\*\*' <<<"$body"; then
      echo "issue-structure: #$issue_num is a work item with no Covers: field (link 4)"
    fi
  fi
done <<<"$issue_numbers"
