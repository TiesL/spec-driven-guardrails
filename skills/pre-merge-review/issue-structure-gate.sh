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
# REST-only (issue #323, reusing model-record-gate.sh's/
# compliance-evidence.sh's already-reviewed design rather than
# re-deriving it independently — see issue #318 for the original
# investigation): the old `gh pr view --json closingIssuesReferences`/
# `gh issue view --json ...` calls this script used to make are
# GraphQL-backed under the hood and 403 from inside a Claude Code
# session — confirmed live for the sibling scripts in #318. This script's
# own fail-open design meant that never crashed, just silently skipped
# link 4 on every single run rather than performing it. Separately,
# `closingIssuesReferences` is only populated by GitHub for a PR whose
# base is the repository's default branch, so even outside the 403 it
# silently missed every closing issue on a release-branch PR — exactly
# the shape that would let a structurally broken work item merge onto
# `release/295-multi-agent-workflow-v1` unnoticed.
#
# Every call below is `gh api repos/{owner}/{repo}/...` against an
# explicit REST endpoint. Closing-issue discovery replaces
# `closingIssuesReferences` with the same closing-keyword scan against
# the PR's own title+body that model-record-gate.sh/
# compliance-evidence.sh use (title included — this repo's own
# release-branch PRs carry the keyword only there).
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

pr_json_part="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" --jq '(.title//"")+"\u0001"+(.body//"")' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: issue-structure-gate couldn't consult PR #$pr_number's title/body (no network or no access) and is skipping link 4." >&2
  echo "$pr_json_part" >&2
  exit 0
fi
pr_title_part="${pr_json_part%%$'\001'*}"
pr_body_part="${pr_json_part#*$'\001'}"

# Same closing-keyword vocabulary as model-record-gate.sh/
# compliance-evidence.sh: close/closes/closed, fix/fixes/fixed,
# resolve/resolves/resolved, optionally followed by ":", required
# whitespace, then "#<issue-number>". Case-insensitive, same as GitHub's
# own parser.
closing_keyword_ere='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'
issue_numbers="$(printf '%s\n%s\n' "$pr_title_part" "$pr_body_part" \
  | grep -oiE "$closing_keyword_ere" | grep -oE '[0-9]+' | sort -un)"

[ -n "$issue_numbers" ] || exit 0

while IFS= read -r issue_num; do
  [ -n "$issue_num" ] || continue

  issue_json_part="$(gh api "repos/{owner}/{repo}/issues/$issue_num" --jq '[(.labels|map(.name)|join(",")), (.body//"")] | join("\u0001")' 2>&1)"
  issue_status=$?
  if [ "$issue_status" -ne 0 ]; then
    echo "warning: issue-structure-gate couldn't consult issue #$issue_num (no network or no access) and is skipping it." >&2
    echo "$issue_json_part" >&2
    continue
  fi
  labels="${issue_json_part%%$'\001'*}"
  body="${issue_json_part#*$'\001'}"

  is_epic=0
  case ",$labels," in
    *,epic,*) is_epic=1 ;;
  esac

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
