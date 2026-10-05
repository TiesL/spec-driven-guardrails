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
if [ ! -r "$script_dir/lib/model-record.sh" ]; then
  echo "warning: review-rounds: lib/model-record.sh not found next to this script, so no rounds were counted." >&2
  exit 0
fi
# shellcheck source=lib/model-record.sh
. "$script_dir/lib/model-record.sh"

# live_text <body>: the body with fenced, tilde-fenced, code-span and blockquote
# text blanked (same as role-label-staleness.sh).
live_text() {
  printf '%s\n' "$1" | awk '
    function drop_spans(s,   out, n, tick, after, p, q, r) {
      out = ""
      while (match(s, /`+/)) {
        n = RLENGTH; tick = substr(s, RSTART, n)
        out = out substr(s, 1, RSTART - 1)
        after = substr(s, RSTART + n)
        p = 0; r = after; q = 0
        while (match(r, /`+/)) {
          if (RLENGTH == n) { p = q + RSTART; break }
          q += RSTART + RLENGTH - 1; r = substr(r, RSTART + RLENGTH)
        }
        if (p == 0) { out = out tick; s = after }        # unmatched run: literal
        else        { out = out " ";  s = substr(after, p + n) }
      }
      return out s
    }
    BEGIN { fch = ""; flen = 0 }
    /^[ \t]*>/ { print ""; next }                         # blockquote first, unchanged by fence state
    {
      line = $0
      if (match(line, /^ ? ? ?`+/) || match(line, /^ ? ? ?~+/)) {
        m = substr(line, RSTART, RLENGTH); sub(/^ +/, "", m)
        if (length(m) >= 3) {
          ch = substr(m, 1, 1); len = length(m)
          rest = substr(line, RSTART + RLENGTH)
          if (fch == "") {                                  # open: any info string allowed
            fch = ch; flen = len; print ""; next
          } else if (ch == fch && len >= flen && rest ~ /^[ \t]*$/) {
            fch = ""; flen = 0; print ""; next               # close: no info string allowed (D10)
          }
        }
      }
      if (fch != "") { print ""; next }
      print drop_spans(line)
    }
  '
}

# rr_rounds: THE round logic (A37). Reads rows on stdin, one per body:
#   created_at<TAB>source<TAB>url<TAB>body
# source is comment | issue | review, url is "-" when unknown (a tab-separated empty field would collapse); newlines in the body are \001. Prints the
# review-round, planning-after and review-rounds lines. Returns 1 when the marker
# reader fails (nothing printed). Moves unchanged to lib/review-rounds.sh (#426).
rr_rounds() {
  local ts src body live scan first stage kind rank seq=0 keyed="" n=0 k1 k4 tab=$'\t'
  while IFS=$'\t' read -r ts src _ body; do
    [ -n "$ts" ] || continue
    seq=$((seq + 1))
    body="$(printf '%s' "$body" | tr '\001' '\n')"
    body="${body//$MARKER_SEP/}"
    live="$(live_text "$body")"
    scan="$(marker_scan "$live$MARKER_SEP")" || return 1
    first="${scan%%$'\n'*}"
    kind=""
    if [ -n "$first" ]; then
      IFS=$'\t' read -r _ stage _ <<<"$first"
      case "$stage" in
        Review) kind=R ;;
        Planning) kind=P ;;
      esac
    elif grep -qE '<!--[[:space:]]*pre-merge-review:done[[:space:]]+sha=[0-9a-fA-F]{40}[[:space:]]*-->' <<<"$live"; then
      kind=R
    fi
    [ -n "$kind" ] || continue
    case "$src" in
      issue) rank=0 ;;
      review) rank=2 ;;
      *) rank=1 ;;
    esac
    keyed="$keyed$(printf '%s\t%s\t%08d\t%s' "$ts" "$rank" "$seq" "$kind")"$'\n'
  done
  [ -n "$keyed" ] && keyed="$(printf '%s' "$keyed" | LC_ALL=C sort -t "$tab" -k1,1 -k2,2n -k3,3n)"
  while IFS=$'\t' read -r k1 _ _ k4; do
    [ -n "$k1" ] || continue
    if [ "$k4" = R ]; then
      n=$((n + 1))
      printf 'review-round: %s at=%s\n' "$n" "$k1"
    elif [ "$n" -gt 0 ]; then
      printf 'planning-after: %s\n' "$n"
    fi
  done <<<"$keyed"
  printf 'review-rounds: %s\n' "$n"
}

# rows_jq <timefield> <source>: gh --jq that turns a REST array into rr_rounds rows.
rows_jq() {
  printf '.[] | select(.%s != null) | [.%s, "%s", ((.html_url // "") | if . == "" then "-" else . end), ((.body // "") | gsub("\\u0001"; " ") | gsub("\\r"; "") | gsub("\\t"; " ") | gsub("\\n"; "\\u0001"))] | join("\\t")' "$1" "$1" "$2"
}

rows=""
failed=0
fetch() { # <endpoint> <timefield> <source> <what>
  local out
  if out="$(gh api "$1" --paginate --jq "$(rows_jq "$2" "$3")" 2>/dev/null)"; then
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
printf '%s\n' "$result"
echo "note: severity is not machine-readable, so this cannot tell which rounds count toward the two-round trigger."
exit 0
