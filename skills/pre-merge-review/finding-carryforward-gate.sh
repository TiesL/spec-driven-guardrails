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
# This compares the two most recent `pre-merge-review:done` comments on
# the PR: every slug the second-to-last comment left `status=open` must
# reappear (open or resolved) in the latest one. Fewer than two review
# comments exist yet -> nothing to carry forward, no findings.
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

pr_number="${1:?usage: finding-carryforward-gate.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: finding-carryforward-gate can't find gh and is skipping the carry-forward check." >&2
  exit 0
fi

comments="$(gh pr view "$pr_number" --json comments --jq '.comments[] | select(.body | contains("pre-merge-review:done")) | .body' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: finding-carryforward-gate couldn't consult PR #$pr_number (no network or no access) and is skipping the check." >&2
  echo "$comments" >&2
  exit 0
fi

# Concatenated comment bodies have no delimiter gh's --jq output can add
# between them, but the marker convention gives one for free: it's always
# the last line of its own comment (see SKILL.md's "ending with the
# required marker"), so a marker line's position is that comment's end.
marker_lines="$(printf '%s' "$comments" | grep -n "pre-merge-review:done" | cut -d: -f1)"
total="$(printf '%s' "$marker_lines" | grep -c . || true)"
[ "$total" -ge 2 ] || exit 0

prevprev_line=0
if [ "$total" -ge 3 ]; then
  prevprev_line="$(printf '%s' "$marker_lines" | sed -n "$((total - 2))p")"
fi
prev_line="$(printf '%s' "$marker_lines" | sed -n "$((total - 1))p")"

# previous: only the second-to-last comment's own body (not all of
# history) — the immediately preceding round, which is what a fresh round
# must account for. latest: only the last comment's body, to end of input.
previous="$(printf '%s' "$comments" | sed -n "$((prevprev_line + 1)),${prev_line}p")"
latest="$(printf '%s' "$comments" | sed -n "$((prev_line + 1)),\$p")"

# Slugs the previous round left open, one per line.
open_slugs="$(printf '%s' "$previous" \
  | grep -oE '<!--[[:space:]]*finding:[^[:space:]]+[[:space:]]+status=open[[:space:]]*-->' \
  | sed -E 's/<!--[[:space:]]*finding:([^[:space:]]+).*/\1/')"
[ -n "$open_slugs" ] || exit 0

printf '%s\n' "$open_slugs" | while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  # <<< here-string, not a piped producer | grep -q: SIGPIPE/pipefail
  # race, see issue #218 and check-no-sigpipe-race.sh.
  if ! grep -qF "finding:$slug" <<<"$latest"; then
    echo "finding-carryforward: $slug was open in the previous round and is missing from this one"
  fi
done
