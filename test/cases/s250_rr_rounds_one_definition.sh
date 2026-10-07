#!/usr/bin/env bash
# S250 — rr_rounds in lib/review-rounds.sh is the one definition of a Review round: what counts, the order, the output rows, the read through rec_scan, and a failed read is never "no round"
# Covers: F42, F40
#
# Issue #426 (slice V5 of #411), AC2 and AC4; Architect A37. Seam: the function
# rr_rounds of lib/review-rounds.sh, sourced ALONE and fed rows on stdin (the
# agreed signature is in test/fixtures/review-rounds-lib-helpers.sh and in the
# stub lib). No gh, no script: the callers are S251 to S253.
#
# Threat model: ACCIDENTAL defects in real PR bodies and in the tools around
# them (a record that lost its closing `-->`, prose before a record, a quoted
# example, an invalid byte, a tool that exits 2, two bodies with one timestamp).
# There is no forger here: a body that hides a record on purpose is the gate's
# business (S130/S243), not this function's.
#
# What it pins (A37 and the issue):
#   D1 a round is ONE body whose FIRST candidate is stage=Review: an ok record, or
#      a near-miss (unclosed, prose before it, blank model, text after it, a
#      value with `<`); a legacy body with no candidate and a live done marker
#      with a 40-hex sha is a round; a quoted record (fence, tilde fence,
#      blockquote, code span, indented block) is no candidate and no round; a body
#      whose first candidate is another stage is no round even with a Review
#      record after it; two Review records, or a record plus a done marker, are ONE
#      round; a done marker that is prose, short, without a sha or quoted is none;
#   D2 order: created_at, then source issue < comment < review, then input order;
#      rounds are numbered 1..n in that order; a Planning-first body after round n
#      is a `P` row with n, one before any round is no row;
#   D3 output rows: six tab separated fields, the body field is the input field
#      unchanged; no rounds is status 0 and empty stdout;
#   D4 the records are read THROUGH rec_scan (a stand-in rec_scan that says "no
#      candidate" makes a real Review record no round; one that says "Review" makes
#      plain prose a round; the kind passed is model-record);
#   D5 a failed read is never "no round": with grep or awk (and every other tool the
#      function turns out to call) failing, stdout is EMPTY, stderr has a line and
#      the status is non-zero; the failure shim must have run; grep exit 1 is a
#      clean "no hit";
#   D6 the same result under LC_ALL=C, a UTF-8 UTF8 and LANG-only environment, with an
#      invalid and a truncated UTF-8 byte before a record.
#
# Red today: the stub returns 99 (every D1 to D3 and D6 arm fails on its assertion;
# D5's baseline fails and its shim is never called). Kill table (mutations of the
# reference this case must not survive; each is named in the message tag):
#   first-cand   count a body with ANY Review record, not the first candidate
#   near-miss    read ok records only (a near-miss Review is no round)
#   legacy       drop the legacy done marker, or accept it without 40 hex / quoted
#   quoted       treat a quoted record as a candidate (fence, tilde, block, span, indent)
#   twice        count two Review records (or a record and a done marker) twice
#   order        file order instead of time order; swap the tie ranks; unstable tie
#   number       number the rounds in file order, or count Planning rows in n
#   planning     emit a P row before round 1, or let P rows consume a round number
#   rows         change the field count, drop or rewrite the body field
#   own-parser   a model-record regex of its own instead of rec_scan
#   fail-open    ignore a failing grep/awk/sort/tr (a count printed, status 0)
#   partial      print the rounds read before the failure
#   locale       an external tool without LC_ALL=C (the LANG and invalid-byte arms)

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/review-rounds-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"
# shellcheck source=../fixtures/review-rounds-lib-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-lib-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rrl_init "S250" || test_done

NL=$'\n'
BT='`'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z
T4=2026-10-04T10:00:00Z T5=2026-10-05T10:00:00Z
rev="$(rr_review)"
pln="$(rr_planning)"
tst="$(rr_stage Test)"
dsc="$(rr_stage Discovery)"
done_m="$(rr_done)"

# expect <label> <mode> <rows> <want-view>: rr_rounds exits 0 and shows exactly <want-view>.
expect() {
  local label="$1" mode="$2" rows="$3" want="$4"
  rrl_call "$mode" "$rows"
  if [ "$RH_RC" -ne 0 ]; then
    fail "S250/$label [$mode] — rr_rounds exited $RH_RC (stdout: '$RH_OUT', stderr: '$RH_ERR')"
    return 1
  fi
  if ! rrl_nf >/dev/null; then
    fail "S250/rows [$mode] — $label: a row without exactly six tab separated fields: '$RH_OUT'"
    return 1
  fi
  if [ "$(rrl_view)" != "$want" ]; then
    fail "S250/$label [$mode] — expected '$(printf '%s' "$want" | LC_ALL=C tr '\n' '|')', got '$(rrl_view | LC_ALL=C tr '\n' '|')'"
    return 1
  fi
  return 0
}

# =========================================================================
# D1 what counts as a round: one body, one row each, alone in its input
# =========================================================================
one() { # <label> <1|0> <body>
  local label="$1" want="$2" body="$3" mode exp=""
  [ "$want" = 1 ] && exp="R:1:$T1:comment"
  for mode in $RH_MODES; do
    expect "$label" "$mode" "$(rrl_row "$T1" comment "$body")" "$exp"
  done
}
one "ok Review record" 1 "round:${NL}${rev}"
one "near-miss unclosed" 1 '<!-- model-record: stage=Review model="x" floor-basis="no closing'
one "near-miss prose before the record" 1 "Reviewer says: ${rev}"
one "near-miss blank model" 1 '<!-- model-record: stage=Review model="" floor-basis="f" -->'
one "near-miss text after the record" 1 "${rev} and more"
one "near-miss value with <" 1 '<!-- model-record: stage=Review model="a<b" floor-basis="f" -->'
one "legacy done marker only" 1 "legacy round:${NL}${done_m}"
one "Review record and done marker are ONE round" 1 "${rev}${NL}${done_m}"
one "two Review records are ONE round" 1 "${rev}${NL}${rev}"
one "Review near-miss then ok Review are ONE round" 1 "${rev} trailing${NL}${rev}"
one "quoted example, then the live Review record" 1 "Example:${NL}\`\`\`${NL}${tst}${NL}\`\`\`${NL}${rev}"
one "fenced Review record and a live done marker is legacy" 1 "Example:${NL}\`\`\`${NL}${rev}${NL}\`\`\`${NL}${done_m}"
one "plain text" 0 "no marker at all"
one "no body at all" 0 ""
one "Planning record only" 0 "${pln}"
one "Discovery record only" 0 "${dsc}"
one "first candidate Test, then a Review record" 0 "${tst}${NL}${rev}"
one "first candidate Discovery, then Review and a done marker" 0 "${dsc}${NL}${rev}${NL}${done_m}"
one "first candidate a Planning near-miss, then Review" 0 "${pln} trailing${NL}${rev}"
one "fenced Review record" 0 "Example:${NL}\`\`\`${NL}${rev}${NL}\`\`\`"
one "tilde-fenced Review record" 0 "Example:${NL}~~~${NL}${rev}${NL}~~~"
one "blockquoted Review record" 0 "> Reviewer wrote:${NL}> ${rev}"
one "Review record in a code span" 0 "The format is ${BT}${rev}${BT}, as in the skill."
one "Review record in an indented block" 0 "Example:${NL}${NL}    ${rev}"
one "unclosed fence runs to the end of its body" 0 "Example:${NL}\`\`\`${NL}${rev}"
one "fenced done marker" 0 "Example:${NL}\`\`\`${NL}${done_m}${NL}\`\`\`"
one "done marker in prose" 0 "The words pre-merge-review:done in prose, and a decoy: <!-- pre-merge-review:done"
one "done marker without a sha" 0 "<!-- pre-merge-review:done -->"
one "done marker with a 39-hex sha" 0 "<!-- pre-merge-review:done sha=ddddddddddddddddddddddddddddddddddddddd -->"
one "done marker in a blockquote" 0 "> <!-- pre-merge-review:done sha=${RR_SHA40} -->"

# =========================================================================
# D2 order, tie-breaks, numbering, Planning rows; D3 row shape
# =========================================================================
r_a="a${NL}${rev}" r_b="b${NL}${rev}" r_c="c${NL}${rev}"
for mode in $RH_MODES; do
  # time order, whatever the input order, across all three sources
  rows="$(rrl_row "$T4" comment "$r_a")${NL}$(rrl_row "$T1" review "$r_b")${NL}$(rrl_row "$T3" issue "$r_c")${NL}$(rrl_row "$T2" comment "$dsc")"
  expect "time order across sources" "$mode" "$rows" "R:1:$T1:review${NL}R:2:$T3:issue${NL}R:3:$T4:comment"
  # a tie: issue, then comment, then review, whatever the input order
  rows="$(rrl_row "$T1" review "$r_a")${NL}$(rrl_row "$T1" comment "$r_b")${NL}$(rrl_row "$T1" issue "$r_c")"
  expect "tie issue comment review" "$mode" "$rows" "R:1:$T1:issue${NL}R:2:$T1:comment${NL}R:3:$T1:review"
  # a tie inside one source: input order, and every row survives
  rows="$(rrl_row "$T1" comment "first${NL}${rev}")${NL}$(rrl_row "$T1" comment "second${NL}${rev}")"
  rrl_call "$mode" "$rows"
  [ "$RH_RC" -eq 0 ] || fail "S250/tie-input [$mode] — exit $RH_RC"
  [ "$(printf '%s' "$RH_OUT" | LC_ALL=C awk -F '\t' 'NF { print $6 }' | LC_ALL=C tr '\001' ' ' | LC_ALL=C tr '\n' '|')" = "first ${rev}|second ${rev}|" ] \
    || fail "S250/tie-input [$mode] — two comments with one timestamp must keep their input order, got: $(printf '%s' "$RH_OUT" | LC_ALL=C tr '\001' ' ' | LC_ALL=C tr '\t' '~')"
  # Planning rows: none before round 1, one after a round carrying that round's number; no round number is spent on it
  rows="$(rrl_row "$T1" comment "$pln")${NL}$(rrl_row "$T2" comment "$r_a")${NL}$(rrl_row "$T3" comment "$pln")${NL}$(rrl_row "$T4" issue "$pln")${NL}$(rrl_row "$T5" comment "$r_b")"
  expect "planning rows" "$mode" "$rows" "R:1:$T2:comment${NL}P:1:$T3:comment${NL}P:1:$T4:issue${NL}R:2:$T5:comment"
  # zero rounds: status 0, empty stdout; empty input too
  expect "zero rounds" "$mode" "$(rrl_row "$T1" comment "talk")${NL}$(rrl_row "$T2" comment "$tst")" ""
  expect "empty input" "$mode" "" ""
done
# the row itself: six fields, url and body carried through unchanged
for mode in $RH_MODES; do
  body="line one${NL}${rev}${NL}last line: <!-- finding:x status=open -->"
  enc="$(printf '%s' "$body" | LC_ALL=C tr '\n' '\001')"
  row="$(printf '%s\t%s\t%s\t%s' "$T2" review "https://example.test/r/1#x" "$enc")"
  rrl_call "$mode" "$row"
  want="$(printf 'R\t1\t%s\treview\thttps://example.test/r/1#x\t%s' "$T2" "$enc")"
  [ "$RH_RC" -eq 0 ] && [ "$RH_OUT" = "$want" ] \
    || fail "S250/rows [$mode] — expected exactly one row 'R 1 <time> review <url> <body unchanged, still \\001 encoded>', got rc=$RH_RC '$(printf '%s' "$RH_OUT" | LC_ALL=C tr '\001' '^' | LC_ALL=C tr '\t' '~')'"
done

# =========================================================================
# D4 the records are read THROUGH rec_scan
# =========================================================================
RECLOG="$SANDBOX/rec-kinds"
canned_none() { rec_scan() { echo "$1" >> "$RECLOG"; return 0; }; rr_rounds <<<"$1"; }
# shellcheck disable=SC2317  # called through rh_run
canned_review() { rec_scan() { echo "$1" >> "$RECLOG"; printf '1\tok\tReview\t%s\n' '<!-- model-record: stage=Review model="m" -->'; return 0; }; rr_rounds <<<"$1"; }
for mode in $RH_MODES; do
  : > "$RECLOG"
  rh_run "$mode" canned_none "$(rrl_row "$T1" comment "real record:${NL}${rev}")"
  if [ "$RH_RC" -ne 0 ] || [ -n "$(printf '%s' "$RH_OUT" | LC_ALL=C tr -d '[:space:]')" ]; then
    fail "S250/own-parser [$mode] — rec_scan found no candidate, yet rr_rounds printed '$RH_OUT' (rc $RH_RC): the Review record must be read THROUGH rec_scan, not by a pattern of its own"
  fi
  [ -s "$RECLOG" ] || fail "S250/own-parser [$mode] — rr_rounds never called rec_scan for a body with a record"
  : > "$RECLOG"
  rh_run "$mode" canned_review "$(rrl_row "$T1" comment "plain prose, nothing in it")"
  [ "$RH_RC" -eq 0 ] && [ "$(rrl_view)" = "R:1:$T1:comment" ] \
    || fail "S250/own-parser [$mode] — rec_scan said the first candidate is Review, yet rr_rounds did not count the body (rc $RH_RC, out '$RH_OUT'): the round must follow rec_scan's rows"
  if [ -s "$RECLOG" ] && [ "$(LC_ALL=C grep -avc '^model-record$' "$RECLOG")" -ne 0 ]; then
    fail "S250/own-parser [$mode] — rec_scan was called with a kind other than model-record: $(LC_ALL=C tr '\n' '|' < "$RECLOG")"
  fi
done

# =========================================================================
# D5 a failed read is never "no round"
# =========================================================================
bodies="$(rrl_row "$T1" comment "r1${NL}${rev}")${NL}$(rrl_row "$T2" comment "plain")${NL}$(rrl_row "$T3" review "r3${NL}${rev}")${NL}$(rrl_row "$T4" comment "legacy${NL}${done_m}")"
tools="grep awk sed tr cut head tail sort uniq wc"
n=0
fresh() { n=$((n + 1)); SHIMS="$SANDBOX/shims$n"; CNT="$SANDBOX/count$n"; rm -rf "$SHIMS" "$CNT"; mkdir -p "$SHIMS"; }
shimmed() { rh_with_path "$SHIMS" rrl_feed "$bodies"; }
D5_MODES=C   # the tool shims are locale independent; the locale arms are D6
for mode in $D5_MODES; do
  # baseline: pass-through shims for every tool, the answer is 3 rounds, grep and awk were called
  fresh
  for t in $tools; do rh_shim "$SHIMS" "$t" pass "$CNT.$t" || continue 2; done
  rh_run "$mode" shimmed
  [ "$RH_RC" -eq 0 ] && [ "$(rrl_view)" = "R:1:$T1:comment${NL}R:2:$T3:review${NL}R:3:$T4:comment" ] \
    || fail "S250/baseline [$mode] — with pass-through shims rr_rounds must still find three rounds (rc $RH_RC, out '$(rrl_view | LC_ALL=C tr '\n' '|')', err '$RH_ERR')"
  for t in grep awk; do
    [ "$(rh_count "$CNT.$t")" -gt 0 ] || fail "S250/baseline [$mode] — the $t shim was never called: no failure of it can be injected (a vacuous pass is red)"
  done
  # every tool, failing from its 1st, 2nd, 3rd and 4th call
  for t in $tools; do
    for from in 1 2 3 4; do
      fresh
      rh_shim "$SHIMS" "$t" "failafter:$from" "$CNT" || continue
      rh_run "$mode" shimmed
      c="$(rh_count "$CNT")"
      case "$t" in grep | awk) [ "$c" -ge "$from" ] || fail "S250/$t from call $from [$mode] — the $t shim ran only $c times, so the failure was never injected: the scenario proved nothing" ;; esac
      if [ "$c" -ge "$from" ]; then
        [ "$RH_RC" -ne 0 ] || fail "S250/fail-open $t from call $from [$mode] — status 0 although $t failed (exit 2): a failed read was taken for 'no round' or a short count (stdout: '$(rrl_view | LC_ALL=C tr '\n' '|')')"
        [ -z "$RH_OUT" ] || fail "S250/partial $t from call $from [$mode] — stdout must be EMPTY when the read failed, got: '$(rrl_view | LC_ALL=C tr '\n' '|')'"
        [ -n "$RH_ERR" ] || fail "S250/fail-open $t from call $from [$mode] — a failure says so on stderr (one line at least)"
      fi
    done
  done
  # grep exit 1 (no hit, with the count 0 a real grep -c prints) is not a failure
  fresh
  rrl_shim_nohit "$SHIMS" "$CNT"
  rh_run "$mode" rh_with_path "$SHIMS" rrl_feed "$(rrl_row "$T1" comment "prose only")${NL}$(rrl_row "$T2" comment "more prose")"
  [ "$RH_RC" -eq 0 ] && [ -z "$RH_OUT" ] && [ -z "$RH_ERR" ] \
    || fail "S250/grep-exit-1 [$mode] — grep's exit 1 on bodies without a record is 'no hit', not a failure: status 0, no rows, nothing on stderr; got rc=$RH_RC out='$RH_OUT' err='$RH_ERR'"
  [ "$(rh_count "$CNT")" -gt 0 ] || fail "S250/grep-exit-1 [$mode] — the grep shim was never called (a vacuous pass is red)"
done

# =========================================================================
# D6 locale: an invalid and a truncated UTF-8 byte before a record
# =========================================================================
for mode in $RH_MODES; do
  for bytes in "$MD_FF" "$MD_TRUNC" "$MD_EMDASH"; do
    rows="$(rrl_row "$T1" comment "x${bytes}y${NL}${rev}")${NL}$(rrl_row "$T2" comment "x${bytes}y ${pln}")${NL}$(rrl_row "$T3" review "${done_m} x${bytes}y")"
    expect "bytes before a record" "$mode" "$rows" "R:1:$T1:comment${NL}P:1:$T2:comment${NL}R:2:$T3:review"
  done
done

test_done
