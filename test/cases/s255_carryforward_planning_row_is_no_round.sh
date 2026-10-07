#!/usr/bin/env bash
# S255 — a Planning body (or any non-review body) posted between two Review rounds is no round for the carry-forward gate: it is neither compared nor does it split the comparison
# Covers: F28, F42
#
# Issue #426 (slice V5 of #411); review round 1 of PR #452, finding
# gate-planning-row-guard-untested (the mutant that removes the gate's filter on
# `R` rows survived every test). rr_rounds also returns `P` rows (a Planning-first
# body after a round, an Architect step of #410's loop-back); the gate must read
# only the `R` rows. Seam: the real gate against a recording fake gh with REST data.
#
# Threat model: ACCIDENTAL (an Architect Planning comment lands between two review
# rounds). No forger.
#
#   P1 round 1 (slug open), a Planning comment that does not mention the slug,
#      round 2 carrying the slug -> nothing reported (if the Planning body were a
#      round, round 1 -> Planning would report the slug as missing);
#   P2 round 1, a Planning comment that itself carries an open finding, round 2
#      that carries the round-1 slug but not the Planning one -> nothing reported
#      (a Planning body is no round, so its open slug is nobody's to carry);
#   P3 round 1 (slug open), a Planning comment, round 2 without the slug -> the slug
#      is reported once, as missing from round 2 (the pair is round 1 and round 2,
#      not Planning and round 2); a Planning PR review in the same place, and a
#      Test-stage record comment, behave the same.
#
# Kill table: the gate without its `[ "$kind" = R ] || continue` filter (P1, P2, P3).

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
[ -x "$GATE" ] || { fail "S255 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S255 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
pln="$(rr_planning)"
op() { rr_finding "$1" open; }

# expect <label> <slugs>: the gate exits 0 and reports exactly those slugs (space separated, may be empty).
expect() {
  local label="$1" want got
  want="$(printf '%s\n' $2 | LC_ALL=C sort | LC_ALL=C sed '/^$/d')"
  rr_script_run "$GATE" "$RR_PR"
  got="$(rr_gate_slugs | LC_ALL=C sed '/^$/d')"
  [ "$rr_status" -eq 0 ] || fail "S255/$label — exit $rr_status, stderr: $rr_err"
  [ "$got" = "$want" ] || fail "S255/$label — expected '$(printf '%s' "$want" | LC_ALL=C tr '\n' ' ')', got '$(printf '%s' "$got" | LC_ALL=C tr '\n' ' ')' (stdout: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|'); stderr: $rr_err)"
}
r1="round 1${NL}$(op keep)${NL}${rev}${NL}${dn}"
r2="round 2, keep carried${NL}$(op keep)${NL}${rev}${NL}${dn}"
r2b="round 2, keep not mentioned${NL}${rev}${NL}${dn}"

# P1
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "architect plan, no findings${NL}${pln}" "$T3" "$r2"
expect "P1 planning comment between two rounds, slug carried" ""
# P1b: the Planning body as a PR review
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T3" "$r2"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "plan as a review${NL}${pln}"
expect "P1b planning review between two rounds, slug carried" ""
# P1c: a Test-stage record comment (not a round, not a planning row)
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "qa notes${NL}$(rr_stage Test)" "$T3" "$r2"
expect "P1c test-stage record between two rounds, slug carried" ""

# P2
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "plan${NL}$(op plan-only)${NL}${pln}" "$T3" "$r2"
expect "P2 an open slug in a planning body is nobody's to carry" ""

# P3
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "plan, keep is not here${NL}${pln}" "$T3" "$r2b"
expect "P3 slug really dropped in round 2 is still reported, once" "keep"

test_done
