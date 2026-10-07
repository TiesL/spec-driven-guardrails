#!/usr/bin/env bash
# review-rounds.sh — Read-only count of the Review rounds on one PR (#410, A28).
#
# Usage:
#   review-rounds.sh <pr-number> [<issue-number>]
#
# Prints, in time order:
#   review-round: <n> at=<timestamp>   one per Review round
#   planning-after: <n>                a Planning marker after round <n>, on the
#                                      PR or on the given issue (reported once,
#                                      against the latest round before it)
#   review-rounds: <N>                 the summary
#   a fixed line saying severity is not machine-readable
#
# A round is A37's: one body (a PR comment or a PR review), counted once, only
# when its FIRST live marker is a Review marker (well-formed or malformed); a
# body with no model-record marker but a pre-merge-review:done marker (the
# HTML-comment form with a 40-hex sha) is a legacy round. Quoted examples (fenced, tilde-fenced, code span, blockquote)
# never count. Order is created_at / submitted_at; ties: issue comments, PR comments, PR reviews.
#
# Limit: severity is prose, not in any marker, so this cannot say whether a
# round counts toward the two-round trigger. Class and severity are judgments;
# the script only shows how many rounds happened and where a Planning step sits.
#
# Not a gate and wired into nothing: it never blocks and ALWAYS exits 0. A
# failed fetch is a warning on stderr and no `review-rounds:` line, so it never
# reads as a count of zero. REST only (`gh api` GET), writes nothing. The marker
# grammar is read through lib/model-record.sh (A25).
#
# Needs gh; the --jq filtering is gh's own. Bash 3.2, BSD tools.

set -uo pipefail
export LC_ALL=C  # A32c: every command and bash's own matching reads GitHub text as bytes; enforced by S235

usage() { echo "usage: review-rounds.sh <pr-number> [<issue-number>] (numbers must be positive integers)" >&2; exit 0; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
for a in "$@"; do
  case "$a" in
    ''|*[!0-9]*|0) usage ;;
  esac
done
pr_number="$1"
issue_number="${2:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: review-rounds: gh not found on PATH, so no rounds were counted." >&2
  exit 0
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ ! -r "$script_dir/lib/review-rounds.sh" ]; then
  echo "warning: review-rounds: lib/review-rounds.sh not found next to this script, so no rounds were counted." >&2
  exit 0
fi
# shellcheck source=lib/review-rounds.sh
. "$script_dir/lib/review-rounds.sh"

# rr_rounds (the one definition of a round, A37) and rr_rows_jq come from lib/review-rounds.sh (#426).

rows=""
failed=0
fetch() { # <endpoint> <timefield> <source> <what>
  local out
  if out="$(gh api "$1" --paginate --jq "$(rr_rows_jq "$2" "$3")" 2>/dev/null)"; then
    [ -z "$out" ] || rows="$rows$out"$'\n'
  else
    echo "warning: review-rounds could not read $4 (no network or no access), so no count is printed." >&2
    failed=1
  fi
}
fetch "repos/{owner}/{repo}/issues/$pr_number/comments" created_at comment "the comments of PR #$pr_number"
fetch "repos/{owner}/{repo}/pulls/$pr_number/reviews" submitted_at review "the reviews of PR #$pr_number"
if [ -n "$issue_number" ]; then
  fetch "repos/{owner}/{repo}/issues/$issue_number/comments" created_at issue "the comments of issue #$issue_number"
fi
[ "$failed" -eq 0 ] || exit 0

if ! result="$(rr_rounds <<<"$rows")"; then
  echo "warning: review-rounds could not read the markers (the marker reader failed), so no count is printed." >&2
  exit 0
fi
rounds=0
tab=$'\t'
while IFS="$tab" read -r kind n ts _; do
  [ -n "$kind" ] || continue
  if [ "$kind" = R ]; then
    rounds="$n"
    printf 'review-round: %s at=%s\n' "$n" "$ts"
  else
    printf 'planning-after: %s\n' "$n"
  fi
done <<<"$result"
printf 'review-rounds: %s\n' "$rounds"
echo "note: severity is not machine-readable, so this cannot tell which rounds count toward the two-round trigger."
exit 0
