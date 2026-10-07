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
# A gap (A37b) is a slug open in round k-1 and not mentioned in round k. It is
# cleared by any later round that mentions the slug, open or resolved. So the
# gate reports a slug if, and only if, the latest round that mentions it leaves
# it open and is not the last round; the line names the round after that one,
# the round that dropped it. One line per slug. "Mentions" is `finding:<slug>`
# anywhere in the round (unchanged; the slug reading is out of scope, #347).
#
# Fail-open without gh or network: warn, don't block — same ground rule
# as every other gate here.
#
# Output on stdout: one line per finding that vanished, sorted by round, then slug:
#   "finding-carryforward: <slug> was open in the previous round and is missing from this one (round <k>)"
# k is the A37 round number (1-based, as review-rounds.sh numbers them).
#
# Every external command here must fail the read when it prints nothing with status 0
# (bash 3.2 does that when a command substitution cannot make its pipe): a warning
# and no verdict, never "no round" or "no finding" (S256).
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

NL=$'\n'
tab=$'\t'
OPEN_RE='<!--[[:space:]]*finding:[^[:space:]]+[[:space:]]+status=open[[:space:]]*-->'

# read_open <body>: sets OPEN to the slugs the body leaves status=open, one per line.
# Counts first (grep -c prints a count whenever it ran), so "status 0, nothing printed"
# and "here-string not made" are told apart from "no finding".
OPEN=""
read_open() {
  local hits rc s
  OPEN=""
  hits="$(LC_ALL=C grep -aEc "$OPEN_RE" <<<"$1")"
  rc=$?
  case "$hits" in
    "" | *[!0-9]*) skip "could not read the findings (grep printed no count, exit $rc)" ;;
  esac
  if [ "$hits" -eq 0 ]; then
    [ "$rc" -eq 1 ] || skip "could not read the findings (grep exit $rc)"
    return 0
  fi
  [ "$rc" -eq 0 ] || skip "could not read the findings (grep exit $rc)"
  s="$(LC_ALL=C grep -aoE "$OPEN_RE" <<<"$1")"
  rc=$?
  { [ "$rc" -eq 0 ] && [ -n "$s" ]; } || skip "could not read the findings (grep -o exit $rc, printed nothing)"
  s="$(LC_ALL=C sed -E 's/<!--[[:space:]]*finding:([^[:space:]]+).*/\1/' <<<"$s")"
  rc=$?
  { [ "$rc" -eq 0 ] && [ -n "$s" ]; } || skip "could not read the findings (sed exit $rc, printed nothing)"
  OPEN="$s"
}

# is_open <slug>: 0 when OPEN lists it. Pure bash, nothing to fail.
is_open() { case "$NL$OPEN$NL" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }

# mentioned <slug> <body>: 0 when the body has finding:<slug> anywhere (open or resolved).
mentioned() {
  local c rc
  c="$(LC_ALL=C grep -acF -e "finding:$1" <<<"$2")"
  rc=$?
  case "$c" in
    "" | *[!0-9]*) skip "could not compare the rounds (grep printed no count, exit $rc)" ;;
  esac
  if [ "$rc" -ge 2 ] || { [ "$rc" -eq 1 ] && [ "$c" != 0 ]; } || { [ "$rc" -eq 0 ] && [ "$c" = 0 ]; }; then
    skip "could not compare the rounds (grep exit $rc)"
  fi
  [ "$rc" -eq 0 ]
}

# One walk over the rounds. cands holds one line per slug that was ever open:
# <slug> TAB <latest round that mentions it> TAB <1 if that round leaves it open>.
cands=""
names="$NL"
n=0
rest_rounds="$rounds"
while [ -n "$rest_rounds" ]; do
  case "$rest_rounds" in
    *"$NL"*) row="${rest_rounds%%"$NL"*}"; rest_rounds="${rest_rounds#*"$NL"}" ;;
    *) row="$rest_rounds"; rest_rounds="" ;;
  esac
  [ "${row%%"$tab"*}" = R ] || continue
  body="${row#*"$tab"}"; body="${body#*"$tab"}"; body="${body#*"$tab"}"; body="${body#*"$tab"}"; body="${body#*"$tab"}"
  n=$((n + 1))
  body="$(printf '%s' "$body" | LC_ALL=C tr '\001' '\n')" || skip "could not decode a round (tr failed)"
  [ -n "$body" ] || skip "could not decode a round (tr printed nothing)"
  read_open "$body"
  newc=""
  rest_c="$cands"
  while [ -n "$rest_c" ]; do
    line="${rest_c%%"$NL"*}"; rest_c="${rest_c#*"$NL"}"
    slug="${line%%"$tab"*}"; r="${line#*"$tab"}"; r="${r%%"$tab"*}"; o="${line##*"$tab"}"
    if mentioned "$slug" "$body"; then
      r="$n"
      if is_open "$slug"; then o=1; else o=0; fi
    fi
    newc="$newc$slug$tab$r$tab$o$NL"
  done
  rest_o="$OPEN"
  while [ -n "$rest_o" ]; do
    case "$rest_o" in
      *"$NL"*) slug="${rest_o%%"$NL"*}"; rest_o="${rest_o#*"$NL"}" ;;
      *) slug="$rest_o"; rest_o="" ;;
    esac
    case "$names" in *"$NL$slug$NL"*) continue ;; esac
    names="$names$slug$NL"
    newc="$newc$slug$tab$n${tab}1$NL"
  done
  cands="$newc"
done

# Report: the latest mention leaves it open and is not the last round.
keys=""
rest_c="$cands"
while [ -n "$rest_c" ]; do
  line="${rest_c%%"$NL"*}"; rest_c="${rest_c#*"$NL"}"
  slug="${line%%"$tab"*}"; r="${line#*"$tab"}"; r="${r%%"$tab"*}"; o="${line##*"$tab"}"
  if [ "$o" = 1 ] && [ "$r" -lt "$n" ]; then
    keys="$keys$(printf '%08d' $((r + 1)))$tab$slug$NL"
  fi
done
if [ -n "$keys" ]; then
  keys="$(LC_ALL=C sort -t "$tab" -k1,1 -k2,2 <<<"$keys")" || skip "could not order the findings (sort failed)"
  [ -n "$keys" ] || skip "could not order the findings (sort printed nothing)"
  out=""
  while [ -n "$keys" ]; do
    case "$keys" in
      *"$NL"*) line="${keys%%"$NL"*}"; keys="${keys#*"$NL"}" ;;
      *) line="$keys"; keys="" ;;
    esac
    [ -n "$line" ] || continue
    out="$out""finding-carryforward: ${line#*"$tab"} was open in the previous round and is missing from this one (round $((10#${line%%"$tab"*})))"$NL
  done
  printf '%s' "$out"
fi
exit 0
