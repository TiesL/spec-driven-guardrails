#!/usr/bin/env bash
# S287 — an issue comment carrying a Review record is no PR Review round: review-rounds.sh and the carry-forward gate count the same PR rounds when the issue holds a Review record and a later Planning record (A37c)
# Covers: F42, F28
#
# Issue #470 AC1-AC4 (PR #469 finding issue-review-counted-as-pr-round); A37, A37c.
# Seam: the two real scripts on one recording fake gh (as S253), which also serves
# the issue-comments endpoint for the issue number given to review-rounds.sh.
# Threat model: ACCIDENTAL (the #408 holistic Review is an issue comment carrying a
# genuine Review record). No forger.
#
# Kill table: count issue Review as a round (A, B, C, D); downgrade it to a Planning
# row (A: extra planning-after); drop the issue Planning row (A, B); a filter in
# review-rounds.sh instead of the lib (passes here, S250 new arms fail: the pair
# catches it); make the gate read the issue endpoint; change a line format.

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
LIB="$TEST_REPO_ROOT/lib/review-rounds.sh"
[ -x "$RRS" ] || { fail "S287 — review-rounds.sh is missing or not executable"; test_done; }
[ -x "$GATE" ] || { fail "S287 — finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S287 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup
# init for shellcheck only (rr_run sets them); non-zero so an unset status fails
rr_out="" rr_status=1

NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z T4=2026-10-04T10:00:00Z
rev="$(rr_review)"
pln="$(rr_planning)"
dn="$(rr_done)"
op() { rr_finding "$1" open; }

# lines <want-lines, newline separated> <label> <script args...>: review-rounds.sh stdout minus the fixed note line.
rrs_lines() { # <label> <want> [<issue>]
  local label="$1" want="$2" issue="${3:-}" got
  rr_script_run "$RRS" "$RR_PR" $issue
  [ "$rr_status" -eq 0 ] || fail "S287/$label — review-rounds.sh exit $rr_status"
  got="$(printf '%s\n' "$rr_out" | LC_ALL=C grep -aE '^(review-round: |planning-after: |review-rounds: )')"
  [ "$got" = "$want" ] || fail "S287/$label — review-rounds.sh printed '$(printf '%s' "$got" | LC_ALL=C tr '\n' '|')', expected '$(printf '%s' "$want" | LC_ALL=C tr '\n' '|')'"
}
# gate <label> <want slugs, space separated>
gate() {
  local label="$1" want got
  want="$(printf '%s\n' $2 | LC_ALL=C sort | LC_ALL=C sed '/^$/d')"
  rr_script_run "$GATE" "$RR_PR"
  [ "$rr_status" -eq 0 ] || fail "S287/$label — the gate exit $rr_status"
  got="$(rr_gate_slugs | LC_ALL=C sed '/^$/d')"
  [ "$got" = "$want" ] || fail "S287/$label — the gate reported '$(printf '%s' "$got" | LC_ALL=C tr '\n' ' ')', expected '$(printf '%s' "$want" | LC_ALL=C tr '\n' ' ')'"
}

# arm A (the AC4 falsifier): issue Review T1, PR Review T2 (x open), issue Planning T3
arm_a() { # <issue T1 body>
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_ISSUE.json" created_at "$T1" "$1" "$T3" "$pln"
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T2" "round${NL}$(op x)${NL}${rev}"
}
A_WANT="review-round: 1 at=$T2${NL}planning-after: 1${NL}review-rounds: 1"
arm_a "issue holistic review${NL}$(op z)${NL}${rev}"
rrs_lines "A" "$A_WANT" "$RR_ISSUE"
gate "A gate" ""

# arm B: arm A plus a PR review at T4 that does not mention x
arm_a "issue holistic review${NL}$(op z)${NL}${rev}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T4" "round 2, nothing mentioned${NL}${rev}"
rrs_lines "B" "review-round: 1 at=$T2${NL}planning-after: 1${NL}review-round: 2 at=$T4${NL}review-rounds: 2" "$RR_ISSUE"
gate "B gate" "x"

# arm C: issue Review T1, PR comment T2 a human sentence only
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_ISSUE.json" created_at "$T1" "issue holistic review${NL}${rev}"
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T2" "Just a human sentence."
rrs_lines "C" "review-rounds: 0" "$RR_ISSUE"
gate "C gate" ""

# arm D: arm A with a legacy done marker on the issue instead of the record
arm_a "legacy issue round${NL}$(op z)${NL}${dn}"
rrs_lines "D" "$A_WANT" "$RR_ISSUE"
gate "D gate" ""

# arm E (control): arm A, no issue number: same rounds, no planning-after
arm_a "issue holistic review${NL}$(op z)${NL}${rev}"
rrs_lines "E" "review-round: 1 at=$T2${NL}review-rounds: 1"
gate "E gate" ""

# the header comments no longer claim an issue row may be an R, and say Planning-only
for f in "$RRS" "$LIB"; do
  if LC_ALL=C grep -qE 'issue (comment|row|body)s?[^.]*(may be|can be|is) an? `?R`?' "$f" || ! LC_ALL=C grep -q 'Planning-only' "$f"; then
    fail "S287/header — $f must say source issue is Planning-only (term 'Planning-only') and no longer claim an issue row may be an R"
  fi
done

test_done
