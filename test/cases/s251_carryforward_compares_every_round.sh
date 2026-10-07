#!/usr/bin/env bash
# S251 — the carry-forward gate compares each Review round with the one immediately before it, request-changes rounds without a done marker included; a human comment is no round
# Covers: F28, F42
#
# Issue #426 (slice V5 of #411) AC1; issue #421 (found on PR #397: round 5 was
# compared with round 2, because only bodies with `pre-merge-review:done` were
# rounds and a request-changes round never carries one). Architect A34 (F1) as
# superseded by A37: a round is the A37 round (S250), every round is compared
# with the round before it, a finding is the `finding:<slug>` marker (reading
# unchanged). Seam: the real gate against a recording fake gh that serves REST
# data (comments and reviews with real timestamps); the data is shaped as the API
# shapes it, so a gate that still asked `gh pr view` would see nothing (S252).
#
# Threat model: ACCIDENTAL (a round type the old filter did not know, a human
# comment between rounds, an endpoint order that is not time order). No forger.
#
# Cases:
#   A  #421's three-round case, the middle round a PR review without a done marker,
#      and again as a PR comment without a done marker: slug a open in round 1,
#      missing from round 2, present again in round 3 -> reported. A gate that
#      compares only the done-marker rounds (1 and 3) says nothing;
#   B  five rounds, three of them request-changes without a done marker: exactly the
#      two findings that vanished are reported (c, d), and b, which round 3 carried,
#      is not (a gate comparing round 5 with round 2 reports b and misses c and d);
#   C  nothing to report: every open slug carried (open or resolved); one round;
#      no round; open findings only in the last round;
#   D  a human comment between two rounds is no round: it cannot carry a slug
#      forward, and it does not split the comparison;
#   E  several open slugs: one line each; an inline marker (prose around it on the
#      line) is read; the output holds finding lines and nothing else; exit 0.
#
# Red today: the gate calls `gh pr view --json comments`, which the fake (REST
# only, like a Claude Code session, #318) refuses, so it fails open and reports
# nothing. Kill table (mutations of the reference this case must not survive):
#   done-only    rounds are the bodies with a done marker (A, B)
#   last-pair    compare only the two latest rounds (A, B)
#   skip-review  read PR comments only (A with the review, B)
#   every-body   every comment is a round (D)
#   first-round  never compare round 1 with round 2 (A, E)
#   all-open     report every open slug of every round, found again or not (B, C)
#   no-resolved  a resolved marker in the next round does not count as carried (C)
#   extra-out    print anything but the finding lines on stdout (E)

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

GATE="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$GATE" ] || { fail "S251 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S251 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0 # set by rr_run
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z
T4=2026-10-04T10:00:00Z T5=2026-10-05T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
op() { rr_finding "$1" open; }
rs() { rr_finding "$1" resolved; }

# gate_expect <label> <slugs, space separated, may be empty>: runs the gate for the PR
# in the fake data and checks exactly those slugs are reported, once each.
gate_expect() {
  local label="$1" want got line
  want="$(printf '%s\n' $2 | LC_ALL=C sort | LC_ALL=C sed '/^$/d')"
  rr_script_run "$GATE" "$RR_PR"
  if [ "$rr_status" -ne 0 ]; then
    fail "S251/$label — exit $rr_status (the gate reports on stdout and exits 0), stderr: $rr_err"
  fi
  got="$(rr_gate_slugs | LC_ALL=C sed '/^$/d')"
  if [ "$got" != "$want" ]; then
    fail "S251/$label — expected the findings '$(printf '%s' "$want" | LC_ALL=C tr '\n' ' ')', got '$(printf '%s' "$got" | LC_ALL=C tr '\n' ' ')' (stdout: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|'); stderr: $rr_err)"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "finding-carryforward: "*" was open in the previous round and is missing from this one"*) : ;;
      *) fail "S251/$label — stdout holds a line that is not a finding line: '$line'" ;;
    esac
  done <<<"$rr_out"
}

# ---- A: #421's case, the middle round without a done marker ---------------------
r1="round 1:${NL}- a thing is missing${NL}$(op a)${NL}${rev}${NL}${dn}"
r2="request changes, nothing about a:${NL}${rev}"
r3="round 3, a is mentioned again:${NL}$(rs a)${NL}${rev}${NL}${dn}"
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T3" "$r3"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "$r2"
gate_expect "A review in the middle" a
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "$r2" "$T3" "$r3"
gate_expect "A comment in the middle" a
# the same three rounds, the first one a PR review, the last one a PR review
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T2" "$r2"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T1" "$r1" "$T3" "$r3"
gate_expect "A reviews around a comment" a

# ---- B: five rounds, three of them request-changes without a done marker ---------
b1="round 1, clean:${NL}${rev}${NL}${dn}"
b2="round 2:${NL}$(op b)${NL}${rev}${NL}${dn}"
b3="request changes, b carried, c new:${NL}$(rs b)${NL}$(op c)${NL}${rev}"
b4="request changes, c vanished, d new:${NL}$(op d)${NL}${rev}"
b5="round 5, d vanished, c mentioned:${NL}$(rs c)${NL}${rev}${NL}${dn}"
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$b1" "$T2" "$b2" "$T4" "$b4" "$T5" "$b5"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T3" "$b3"
gate_expect "B five rounds" "c d"

# ---- C: nothing to report ---------------------------------------------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "r1${NL}$(op x)${NL}$(op y)${NL}${rev}${NL}${dn}" \
  "$T3" "r3${NL}$(op x)${NL}$(rs y)${NL}$(op z)${NL}${rev}${NL}${dn}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "r2${NL}$(op x)${NL}$(op y)${NL}${rev}"
gate_expect "C carried or resolved in every next round" ""
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(op a)${NL}${rev}${NL}${dn}"
gate_expect "C one round" ""
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "just a comment" "$T2" "$(rr_stage Test)"
gate_expect "C no round" ""
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}${rev}${NL}${dn}" "$T2" "r2${NL}$(op last)${NL}${rev}${NL}${dn}"
gate_expect "C open only in the last round" ""

# ---- D: a human comment is no round ------------------------------------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "r1${NL}$(op e)${NL}${rev}${NL}${dn}" \
  "$T2" "Looks fixed to me: $(rs e)" \
  "$T3" "r2, e is not mentioned${NL}${rev}${NL}${dn}"
gate_expect "D a human comment cannot carry a finding forward" e
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "r1${NL}$(op e)${NL}${rev}${NL}${dn}" \
  "$T2" "chatter with no marker at all" \
  "$T3" "r2, e carried${NL}$(op e)${NL}${rev}${NL}${dn}"
gate_expect "D a human comment between rounds splits nothing" ""

# ---- E: several slugs, inline markers, only finding lines ---------------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "r1${NL}$(op one)${NL}Prose before $(op inline-slug) and prose after.${NL}$(op three)${NL}${rev}${NL}${dn}" \
  "$T2" "r2${NL}$(rs three)${NL}${rev}${NL}${dn}"
gate_expect "E several slugs and an inline marker" "one inline-slug"
n="$(printf '%s\n' "$rr_out" | LC_ALL=C grep -ac '^finding-carryforward: ')"
[ "$n" -eq 2 ] || fail "S251/E — two vanished findings must give two lines, got $n: $rr_out"

test_done
