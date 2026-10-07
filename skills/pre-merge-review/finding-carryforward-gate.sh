#!/usr/bin/env bash
# skills/pre-merge-review/finding-carryforward-gate.sh — #241 AC2: makes
# sure a finding from an earlier review round survives into the next one
# instead of silently vanishing because that round ran fresh-context.
#
# Usage:
#   finding-carryforward-gate.sh <pr-number>
#
# Fresh-context review is correct and deliberate (that's the whole point
# of a second, independent look) — but nothing tracked which findings a
# prior round left open, so a fresh round had no way to know one was still
# outstanding. Found via #238 (portfolio-mgt-agents PR #4): round 1 flagged
# a missing Decision Log entry; round 2 never carried it forward; the PR
# merged 17 seconds later.
#
# Each individual finding in a pre-merge-review comment carries its own
# marker:
#   <!-- finding:<slug> status=open -->
#   <!-- finding:<slug> status=resolved -->
#
# This compares every Review round with the one immediately before it
# (#421, #426): a round is the A37 round (lib/review-rounds.sh, one
# definition shared with review-rounds.sh), a PR comment or a PR review, so a
# request-changes round with no `pre-merge-review:done` marker counts. Every
# slug a round left `status=open` must reappear (open or resolved) in the
# next one. Fewer than two rounds -> nothing to carry forward, no findings.
# The PR description is no round.
#
# Fail-open without gh or network: warn, don't block — same ground rule
# as every other gate here.
#
# Output on stdout: one line per finding that vanished:
#   "finding-carryforward: <slug> was open in the previous round and is missing from this one"
#
# No `eval`. PR comment text isn't under this script's control.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail
export LC_ALL=C  # A32c: every command and bash's own matching reads GitHub text as bytes; enforced by S235

pr_number="${1:?usage: finding-carryforward-gate.sh <pr-number>}"

skip() { # <what failed>: fail open, a warning, no verdict
  echo "warning: finding-carryforward-gate $1 and is skipping the carry-forward check for PR #$pr_number." >&2
  exit 0
}

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: finding-carryforward-gate can't find gh and is skipping the carry-forward check." >&2
  exit 0
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || skip "could not find its own directory"
# shellcheck source=lib/review-rounds.sh
. "$script_dir/../../lib/review-rounds.sh" || skip "could not load lib/review-rounds.sh"

rows=""
fetch() { # <endpoint> <timefield> <source>
  local out
  out="$(gh api "$1" --paginate --jq "$(rr_rows_jq "$2" "$3")" 2>/dev/null)" \
    || skip "couldn't consult PR #$pr_number (no network or no access)"
  [ -z "$out" ] || rows="$rows$out"$'\n'
}
fetch "repos/{owner}/{repo}/issues/$pr_number/comments" created_at comment
fetch "repos/{owner}/{repo}/pulls/$pr_number/reviews" submitted_at review

rounds="$(rr_rounds <<<"$rows")" || skip "couldn't read the review rounds"

tab=$'\t'
out=""
prev=""
have_prev=0
while IFS="$tab" read -r kind _ _ _ _ body; do
  [ "$kind" = R ] || continue
  body="$(printf '%s' "$body" | LC_ALL=C tr '\001' '\n')" || skip "could not decode a round (tr failed)"
  if [ "$have_prev" -eq 1 ]; then
    # Slugs the previous round left open, one per line. grep exit 1 is "none".
    slugs="$(LC_ALL=C grep -aoE '<!--[[:space:]]*finding:[^[:space:]]+[[:space:]]+status=open[[:space:]]*-->' <<<"$prev")"
    rc=$?
    [ "$rc" -le 1 ] || skip "could not read the findings (grep exit $rc)"
    if [ -n "$slugs" ]; then
      slugs="$(LC_ALL=C sed -E 's/<!--[[:space:]]*finding:([^[:space:]]+).*/\1/' <<<"$slugs")" \
        || skip "could not read the findings (sed failed)"
      while IFS= read -r slug; do
        [ -n "$slug" ] || continue
        LC_ALL=C grep -aqF "finding:$slug" <<<"$body"
        rc=$?
        case "$rc" in
          0) : ;;
          1) out="$out""finding-carryforward: $slug was open in the previous round and is missing from this one"$'\n' ;;
          *) skip "could not compare the rounds (grep exit $rc)" ;;
        esac
      done <<<"$slugs"
    fi
  fi
  prev="$body"
  have_prev=1
done <<<"$rounds"
printf '%s' "$out"
exit 0
