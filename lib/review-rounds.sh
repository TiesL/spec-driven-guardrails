#!/usr/bin/env bash
# lib/review-rounds.sh — THE definition of a Review round (A37, #426, slice V5 of #411).
#
# The one definition: review-rounds.sh and finding-carryforward-gate.sh both
# read their rounds through it. Records are read through rec_scan (lib/model-record.sh).
#
# Source, don't execute. Sourcing this file alone gives rr_rounds.
#
#   rr_rounds        reads rows on STDIN, one per body, tab separated:
#                        <created_at> TAB <source> TAB <url> TAB <body>
#                    source is comment | issue | review; url is "-" when unknown;
#                    the body holds its newlines as U+0001. A blank line is ignored.
#                    Prints one row per body that is a Review round, plus one per
#                    body whose first candidate is a Planning record after at least
#                    one round, in time order, six tab separated fields:
#                        R TAB <n> TAB <created_at> TAB <source> TAB <url> TAB <body>
#                        P TAB <n> TAB <created_at> TAB <source> TAB <url> TAB <body>
#                    R: n is the round's 1-based number. P: the number of the latest
#                    round before it. The body field is the input field unchanged.
#                    Order: created_at, then source (issue, comment, review), then
#                    input order. Status 0, also for no round. A failed read (an
#                    external tool, a `[[ =~ ]]` of 2) prints nothing on stdout, one
#                    line on stderr and returns non-zero: never "no round".
#   A round: one body whose first candidate (an ok or near-miss model-record line,
#   read through rec_scan model-record; a quoted one is not a candidate) is
#   stage=Review, or a body with no candidate and a live
#   `pre-merge-review:done sha=<40 hex>` marker (legacy).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# shellcheck source=lib/model-record.sh
. "$(dirname "${BASH_SOURCE[0]}")/model-record.sh"

_rr_fail() { echo "lib/review-rounds.sh: rr_rounds: $1 failed with exit $2; rounds were NOT read" >&2; }

# rr_rows_jq <timefield> <source>: the gh --jq filter that turns one REST array
# (comments, reviews) into rr_rounds input rows. Prints text only.
rr_rows_jq() {
  printf '.[] | select(.%s != null) | [.%s, "%s", ((.html_url // "") | if . == "" then "-" else . end), ((.body // "") | gsub("\\u0001"; " ") | gsub("\\r"; "") | gsub("\\t"; " ") | gsub("\\n"; "\\u0001"))] | join("\\t")' "$1" "$1" "$2"
}

rr_rounds() {
  local tab=$'\t' line ts rest src url body text live scan row cls stage first kind rank seq=0 keyed="" n=0
  local rc k1 k3 k4 out="" rowsarr_seq hit
  local rows
  rows=()
  while IFS= read -r line; do
    ts="${line%%"$tab"*}"
    [ -n "$line" ] && [ -n "$ts" ] || continue
    rest="${line#*"$tab"}"
    src="${rest%%"$tab"*}"
    rest="${rest#*"$tab"}"
    url="${rest%%"$tab"*}"
    body="${rest#*"$tab"}"
    seq=$((seq + 1))
    rows[$seq]="$src$tab$url$tab$body"
    text="$(printf '%s' "$body" | LC_ALL=C tr '\001' '\n')"
    rc=$?
    [ "$rc" -eq 0 ] || { _rr_fail tr "$rc"; return "$rc"; }
    # tr always prints something for a body with a non-\001 byte. On bash 3.2 a failed
    # substitution (no pipe) returns 0 with an empty value, so empty is a failure here.
    if [ -z "$text" ] && [ -n "${body//$'\001'/}" ]; then _rr_fail tr "0 (printed nothing)"; return 2; fi
    scan="$(rec_scan model-record "$text")" || return $?
    first=""
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      IFS=$'\t' read -r _ cls stage _ <<<"$row"
      [ "$cls" != quoted ] || continue
      first="$stage"
      break
    done <<<"$scan"
    kind=""
    case "$first" in
      Review) kind=R ;;
      Planning) kind=P ;;
      "")
        # live_text may legitimately print nothing (all quoted); a sentinel plus its status
        # tells that apart from a substitution that failed and left an empty value.
        live="$(live_text "$text"; printf 'x%s' "$?")"
        case "$live" in
          *x[0-9]*) rc="${live##*x}"; live="${live%x*}" ;;
          *) _rr_fail live_text "(no output)"; return 2 ;;
        esac
        [ "$rc" -eq 0 ] || { _rr_fail live_text "$rc"; return "$rc"; }
        # grep -c, not -q: a here-string that cannot be made returns 1 like "no hit", but
        # it prints no count, and a count is what tells the two apart (as in rec_scan).
        hit="$(LC_ALL=C grep -acE '<!--[[:space:]]*pre-merge-review:done[[:space:]]+sha=[0-9a-fA-F]{40}[[:space:]]*-->' <<<"$live")"
        rc=$?
        case "$hit" in
          "" | *[!0-9]*) _rr_fail grep "$rc (no numeric hit count)"; return 2 ;;
        esac
        if [ "$rc" -ge 2 ] || { [ "$rc" -eq 1 ] && [ "$hit" != 0 ]; } || { [ "$rc" -eq 0 ] && [ "$hit" = 0 ]; }; then
          _rr_fail grep "$rc"; return 2
        fi
        if [ "$rc" -eq 0 ]; then
          # cross-check the count with a plain match: both must agree before it is a round
          LC_ALL=C grep -aqE '<!--[[:space:]]*pre-merge-review:done[[:space:]]+sha=[0-9a-fA-F]{40}[[:space:]]*-->' <<<"$live" \
            || { _rr_fail grep "disagreement between count and match"; return 2; }
          kind=R
        fi
        ;;
    esac
    [ -n "$kind" ] || continue
    case "$src" in
      issue) rank=0 ;;
      review) rank=2 ;;
      *) rank=1 ;;
    esac
    keyed="$keyed$(printf '%s\t%s\t%08d\t%s' "$ts" "$rank" "$seq" "$kind")"$'\n'
  done
  if [ -n "$keyed" ]; then
    keyed="$(LC_ALL=C sort -t "$tab" -k1,1 -k2,2n -k3,3n <<<"$keyed")"
    rc=$?
    [ "$rc" -eq 0 ] || { _rr_fail sort "$rc"; return "$rc"; }
    [ -n "$keyed" ] || { _rr_fail sort "0 (printed nothing)"; return 2; }
  fi
  while IFS=$'\t' read -r k1 _ k3 k4; do
    [ -n "$k1" ] || continue
    rowsarr_seq=$((10#$k3))
    if [ "$k4" = R ]; then
      n=$((n + 1))
    elif [ "$n" -eq 0 ]; then
      continue
    fi
    out="$out$k4$tab$n$tab$k1$tab${rows[$rowsarr_seq]%%"$tab"*}$tab"
    rest="${rows[$rowsarr_seq]#*"$tab"}"
    out="$out$rest"$'\n'
  done <<<"$keyed"
  printf '%s' "$out"
}
