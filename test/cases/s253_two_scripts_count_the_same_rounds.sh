#!/usr/bin/env bash
# S253 — review-rounds.sh and the carry-forward gate count the same Review rounds, in the same order: a PR review is a round like a comment, a near-miss and a legacy body are rounds, a fenced record and the PR description are not
# Covers: F28, F42
#
# Issue #426 (slice V5 of #411) AC2 and AC4; A37 ("one Review round, and one
# latest": the scenario "two Review rounds, one a PR review and one a PR comment,
# with review-rounds.sh and the carry-forward gate counting the same rounds").
# Seam: the two real scripts on the SAME fake REST data (a recording fake gh).
# review-rounds.sh prints its count and the time of each round; the gate prints
# no count, so the data is built so that its findings show which bodies were
# rounds: a finding is open in one body and absent from the body that follows it
# in the expected chain, and any other chain gives a different set of lines.
#
# Threat model: ACCIDENTAL defects in real PR bodies (a record that lost its
# `-->`, a pasted example in a fence, a body from before the records existed, a
# PR description that quotes the format). No forger.
#
#   AC2  comment (t1) -> PR review (t2) -> comment (t3), the review in the other
#        endpoint's list: review-rounds.sh prints `review-rounds: 3` with rounds at
#        t1, t2, t3 in that order; the gate (x open in 1, resolved in 2 where y
#        opens, nothing in 3) reports y and only y (a gate that skips reviews
#        compares 1 with 3 and reports x; one that appends reviews last reports x);
#        the same with the review first and last;
#   AC4  a PR with (N) a near-miss Review body (several shapes), (F) a fenced Review
#        record (fence, tilde, blockquote, code span, indented block) with a resolved
#        marker for N's finding in live text, (L) a legacy done-marker body, (H) a human
#        comment, and a PR description that holds a Review record and an open
#        finding: review-rounds.sh counts exactly N and L (2 rounds, at their times);
#        the gate reports N's finding as missing from L and nothing else (if F
#        counted, N's finding would be carried; if the description counted, its
#        finding would be reported; if N or L did not count, nothing would be reported).
#
# Red today: review-rounds.sh counts through its own copy of the definition and
# the gate through `gh pr view`; the AC4 and AC2 gate arms fail because the gate
# sees no REST data. Kill table:
#   no-reviews    a script that reads PR comments only (AC2)
#   reviews-last  rounds numbered comments first, reviews after (AC2)
#   near-miss     a script that counts ok records only (AC4)
#   legacy        a script that drops legacy bodies (AC4)
#   fence         a script that counts a fenced/quoted record (AC4)
#   description   a script that counts the PR description (AC4)
#   two-owners    one script keeps its own definition (any arm: the counts differ)

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

RRS="$TEST_REPO_ROOT/review-rounds.sh"
GATE="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$RRS" ] || { fail "S253 — review-rounds.sh is missing or not executable"; test_done; }
[ -x "$GATE" ] || { fail "S253 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S253 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
BT='`'
T0=2026-09-30T09:00:00Z T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z
T4=2026-10-04T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
op() { rr_finding "$1" open; }
rs() { rr_finding "$1" resolved; }

# both <label> <want-rounds, "|"-separated times> <want-slugs, space separated>:
# runs both scripts on the data in the fake gh and compares.
both() {
  local label="$1" want_times="$2" want_slugs want_n got_times got_n
  want_slugs="$(printf '%s\n' $3 | LC_ALL=C sort | LC_ALL=C sed '/^$/d')"
  want_n="$(printf '%s' "$want_times" | LC_ALL=C awk -F '|' '{ n = 0; for (i = 1; i <= NF; i++) if ($i != "") n++; print n }')"
  rr_script_run "$RRS" "$RR_PR"
  [ "$rr_status" -eq 0 ] || fail "S253/$label — review-rounds.sh exit $rr_status"
  got_times="$(printf '%s\n' "$rr_out" | LC_ALL=C sed -n -E 's/^review-round: [0-9]+ at=(.*)$/\1/p' | LC_ALL=C tr '\n' '|')"
  got_n="$(printf '%s\n' "$rr_out" | LC_ALL=C sed -n -E 's/^review-rounds: ([0-9]+)$/\1/p')"
  [ "$got_n" = "$want_n" ] || fail "S253/$label — review-rounds.sh counted '$got_n' rounds, expected $want_n ($(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|'))"
  [ "$got_times" = "$want_times" ] || fail "S253/$label — review-rounds.sh listed the rounds '$got_times', expected '$want_times' (same order as the gate walks them)"
  local numbered
  numbered="$(printf '%s\n' "$rr_out" | LC_ALL=C sed -n -E 's/^review-round: ([0-9]+) at=.*$/\1/p' | LC_ALL=C tr '\n' ' ')"
  rr_script_run "$GATE" "$RR_PR"
  [ "$rr_status" -eq 0 ] || fail "S253/$label — the gate exit $rr_status"
  local got
  got="$(rr_gate_slugs | LC_ALL=C sed '/^$/d')"
  [ "$got" = "$want_slugs" ] || fail "S253/$label — the gate reported '$(printf '%s' "$got" | LC_ALL=C tr '\n' ' ')', expected '$(printf '%s' "$want_slugs" | LC_ALL=C tr '\n' ' ')': the rounds it walks are not the ones review-rounds.sh counted ($numbered rounds there; stderr: $rr_err)"
}

# ---- AC2 comment, review, comment (and the review first and last) -------------------
c1="round 1${NL}$(op x)${NL}${rev}${NL}${dn}"
c2="request changes: x fixed, y found${NL}$(rs x)${NL}$(op y)${NL}${rev}"
c3="round 3, nothing left${NL}${rev}${NL}${dn}"
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$c1" "$T3" "$c3"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "$c2"
both "AC2 comment review comment" "$T1|$T2|$T3|" "y"
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T2" "$c2"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T1" "$c1" "$T3" "$c3"
both "AC2 review comment review" "$T1|$T2|$T3|" "y"
# a tie: a comment and a review at the same time are two rounds, comment first
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(op t)${NL}${rev}${NL}${dn}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T1" "r2, t missing${NL}${rev}"
both "AC2 a comment and a review at the same time" "$T1|$T1|" "t"

# ---- AC4 what counts as a round ---------------------------------------------------------
nm_shape() { # <n>: the near-miss body of shape 1 to 3
  case "$1" in
    1) printf '%s' '<!-- model-record: stage=Review model="x" floor-basis="no closing' ;;
    2) printf '%s' "Reviewer says: ${rev}" ;;
    3) printf '%s' '<!-- model-record: stage=Review model="" floor-basis="f" -->' ;;
  esac
}
fe_shape() { # <n>: a quoted Review record of shape 1 to 5
  case "$1" in
    1) printf '%s' "Pasted example:${NL}\`\`\`${NL}${rev}${NL}\`\`\`" ;;
    2) printf '%s' "Pasted example:${NL}~~~${NL}${rev}${NL}~~~" ;;
    3) printf '%s' "> Reviewer wrote:${NL}> ${rev}" ;;
    4) printf '%s' "The format is ${BT}${rev}${BT}, as in the skill." ;;
    5) printf '%s' "Pasted example:${NL}${NL}    ${rev}" ;;
  esac
}
for nm_k in 1 2 3; do
  for fe_k in 1 2 3 4 5; do
    nm="$(nm_shape "$nm_k")"
    fe="$(fe_shape "$fe_k")"
    nbody="near-miss round${NL}$(op n1)${NL}${nm}"
    fbody="${fe}${NL}Resolved: $(rs n1)"
    lbody="legacy round, no model-record${NL}${dn}"
    rr_reset
    rr_pr_json "$T0" "Closes #$RR_ISSUE${NL}${rev}${NL}$(op d0)"
    rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
      "$T1" "$nbody" \
      "$T3" "$lbody" \
      "$T4" "A human comment, no marker."
    rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "$fbody"
    both "AC4 near-miss shape $nm_k with a quoted record of shape $fe_k" "$T1|$T3|" "n1"
  done
done

test_done
