#!/usr/bin/env bash
# S254 — the carry-forward gate names the round that dropped each finding, and a slug that a later round re-flags or resolves is not reported any more (A37b)
# Covers: F28, F42
#
# Issue #426 (slice V5 of #411) AC1 ("reports that slug as missing from round 2");
# review round 1 of PR #452, finding gate-output-names-no-round. Seam: the real
# gate against a recording fake gh that serves REST data (comments and reviews).
#
# Threat model: ACCIDENTAL (a person reading the gate's output after several
# rounds cannot tell which round dropped a slug; a pair that once missed a slug is
# re-reported on every later run and nothing can clear it). No forger.
#
# Expected verdict: Architect ruling A37b (issue #426 comment 6032113503), which
# replaced QA's earlier "open then resolved" reading:
#   rule   a slug is reported iff the LATEST round that mentions it leaves it open
#          (an open marker) and that round is not the last round. The line names the
#          round after it, the round that dropped the slug. Any later round that
#          carries the slug, open or resolved, clears the gap. One line per slug;
#          lines sorted by round, then slug;
#   N      every reported line keeps the existing prefix
#          `finding-carryforward: <slug> was open in the previous round and is missing from this one`
#          and after it names the round that dropped the slug by its A37 number: the
#          token `round <k>` (k = the number rr_rounds gives that round), and no other
#          round number than the pair's own (k-1, k). A human comment is no round and
#          takes no number;
#   table  (m = missing, o = open, r = resolved; the rounds are r1..rn)
#          o m          -> round 2      (N1, N3)
#          o m r        -> no           (T1, H3 flipped from the earlier encoding)
#          o m o        -> no           (T2)
#          o m o o      -> no           (T3)
#          o m o r      -> no           (H alpha, H2)
#          o m o m      -> round 4 only (T4)
#          o m m        -> round 2 once (N1, T5)
#          o m m o      -> no           (T6)
#          o o m        -> round 3      (N2)
#          o o m m      -> round 3 once (H beta)
#          m m o        -> no           (T7: nothing was open before the last round)
#          m m r        -> no           (H3 variant)
#
# Kill table (mutations of the reference this case must not survive):
#   no-round         the suffix does not name a round (N)
#   wrong-round      names the previous round, or the last round, or the file position (N)
#   comment-numbered a human comment takes a round number (N3)
#   forever          every gap is reported on every later run, nothing clears it (H, T1-T3, T6)
#   first-gap-only   a slug is reported once at its first gap, whatever follows (H alpha, T4)
#   silence-all      every gap is dropped once the slug turns up again later, resolved or not (N, H beta)
#   open-then-resolved-only  QA's earlier rule: only an open and then a resolved clears (T1, T2, T3, T6)
#   only-open-heals  a later open clears the gap, a later resolved does not (T1, H3)
#   only-resolved-heals  a later resolved clears the gap, a later open does not (T2, T3, T6)
#   adjacent-only    only the round right after the gap can clear it (T6)
#   latest-gap-lost  reports the first gap's round instead of the latest (T4)
#   dup              one line per missing round after the last open, not one per slug (N1, T5, H beta)
#   skip-last-round  a drop in the last round is not reported (N2)

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
[ -x "$GATE" ] || { fail "S254 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S254 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z T4=2026-10-04T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
op() { rr_finding "$1" open; }
rs() { rr_finding "$1" resolved; }
PREFIX_END=" was open in the previous round and is missing from this one"

# line_for <slug>: the finding line of the gate for that slug (all of them, one per line).
line_for() { printf '%s\n' "$rr_out" | LC_ALL=C grep -a "^finding-carryforward: $1 was open" || true; }

# names_round <label> <slug> <k>: exactly one line for the slug, and after the
# fixed prefix it names `round <k>` and no round number outside {k-1, k}.
names_round() {
  local label="$1" slug="$2" k="$3" line n suffix tok
  n="$(line_for "$slug" | LC_ALL=C grep -ac .)"
  if [ "$n" -ne 1 ]; then
    fail "S254/$label — expected exactly one line for '$slug', got $n (stdout: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|'); stderr: $rr_err)"
    return
  fi
  line="$(line_for "$slug")"
  case "$line" in
    "finding-carryforward: $slug$PREFIX_END"*) : ;;
    *) fail "S254/$label — the line lost the fixed prefix: '$line'"; return ;;
  esac
  suffix="${line#"finding-carryforward: $slug$PREFIX_END"}"
  if ! printf '%s' "$suffix" | LC_ALL=C grep -aqE "(^|[^A-Za-z0-9])round $k([^0-9]|$)"; then
    fail "S254/$label — the line does not name round $k after the prefix (suffix: '$suffix'): a reader cannot tell which round dropped '$slug'"
  fi
  for tok in $(printf '%s' "$suffix" | LC_ALL=C grep -aoE 'round [0-9]+' | LC_ALL=C tr ' ' '_'); do
    case "$tok" in
      "round_$k" | "round_$((k - 1))") : ;;
      *) fail "S254/$label — the line names ${tok/_/ }, which is not a round of the pair (rounds $((k - 1)) and $k): '$suffix'" ;;
    esac
  done
}
run_gate() {
  rr_script_run "$GATE" "$RR_PR"
  [ "$rr_status" -eq 0 ] || fail "S254/$1 — exit $rr_status (the gate reports on stdout and exits 0), stderr: $rr_err"
}

# gate_rounds <body of round 1> ... : rounds r1..rn as PR comments, one per T1..Tn
gate_rounds() {
  local ts=("$T1" "$T2" "$T3" "$T4") args=() i=0 b
  rr_reset
  for b in "$@"; do args+=("${ts[$i]}" "r$((i + 1))${NL}${b}${NL}${rev}${NL}${dn}"); i=$((i + 1)); done
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "${args[@]}"
}
# none <label>: the gate printed no finding line at all
none() {
  local n
  n="$(printf '%s\n' "$rr_out" | LC_ALL=C grep -ac '^finding-carryforward: ')"
  [ "$n" -eq 0 ] || fail "S254/$1 — expected no finding line, got $n: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|') (a later round carried the slug, or the slug was open in the last round only)"
}
# only_one <label> <slug> <k>: exactly one finding line in all, for that slug, naming round k
only_one() {
  local n
  n="$(printf '%s\n' "$rr_out" | LC_ALL=C grep -ac '^finding-carryforward: ')"
  [ "$n" -eq 1 ] || fail "S254/$1 — expected one finding line in all, got $n: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|')"
  names_round "$1" "$2" "$3"
}

# ---- N1: #421's three rounds, the middle one a request-changes PR review -----------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(op alpha)${NL}${rev}${NL}${dn}" "$T3" "r3, nothing about alpha either${NL}${rev}${NL}${dn}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "r2, nothing about alpha${NL}${rev}"
run_gate "N1"
names_round "N1 plain three-round case (S251 A), missing twice" alpha 2
n="$(printf '%s\n' "$rr_out" | LC_ALL=C grep -ac '^finding-carryforward: ')"
[ "$n" -eq 1 ] || fail "S254/N1 — alpha is missing in rounds 2 and 3 and must give one line (round 2), got $n: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|')"

# ---- N2: the drop is in round 3 of three ------------------------------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}${rev}${NL}${dn}" "$T2" "r2${NL}$(op beta)${NL}${rev}${NL}${dn}" "$T3" "r3, beta gone${NL}${rev}${NL}${dn}"
run_gate "N2"
names_round "N2 drop in the last round" beta 3

# ---- N3: a human comment between the rounds takes no number ------------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(op gamma)${NL}${rev}${NL}${dn}" "$T2" "a human remark, no marker" "$T4" "r3${NL}$(op gamma)${NL}${rev}${NL}${dn}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T3" "r2, gamma gone${NL}${rev}"
run_gate "N3"
names_round "N3 round 2 is the review, the human comment has no number" gamma 2

# ---- H: re-flagged and resolved is not reported; a slug that stays missing is -------
# alpha: open r1, missing r2, open r3, resolved r4  -> nothing for alpha
# beta:  open r1, open r2, missing r3, missing r4   -> one line, round 3
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "r1${NL}$(op alpha)${NL}$(op beta)${NL}${rev}${NL}${dn}" \
  "$T2" "r2${NL}$(op beta)${NL}${rev}${NL}${dn}" \
  "$T3" "r3${NL}$(op alpha)${NL}${rev}${NL}${dn}" \
  "$T4" "r4${NL}$(rs alpha)${NL}${rev}${NL}${dn}"
run_gate "H"
if [ -n "$(line_for alpha)" ]; then
  fail "S254/H — alpha went missing in round 2, was flagged open again in round 3 and is resolved in round 4, and the gate still reports it: '$(line_for alpha)' (a gap that was closed cannot be cleared by doing what the skill says)"
fi
names_round "H beta stays missing" beta 3
n="$(printf '%s\n' "$rr_out" | LC_ALL=C grep -ac '^finding-carryforward: ')"
[ "$n" -eq 1 ] || fail "S254/H — expected one line in all (beta), got $n: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|')"

# H2: the same with the resolving round a PR review, and the gap in a review round
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(op alpha)${NL}${rev}${NL}${dn}" "$T3" "r3${NL}$(op alpha)${NL}${rev}${NL}${dn}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "r2, request changes${NL}${rev}" "$T4" "r4, request changes${NL}$(rs alpha)${NL}${rev}"
run_gate "H2"
[ -z "$(line_for alpha)" ] || fail "S254/H2 — alpha closed in a request-changes round 4 after being re-flagged, and the gate still reports it: '$(line_for alpha)'"

# H3 (A37b, flipped): missing in round 2, only resolved in round 3 and again in round 4:
# a resolved round carries the slug explicitly, so nothing is reported
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "r1${NL}$(op alpha)${NL}${rev}${NL}${dn}" \
  "$T2" "r2${NL}${rev}${NL}${dn}" \
  "$T3" "r3${NL}$(rs alpha)${NL}${rev}${NL}${dn}" \
  "$T4" "r4${NL}$(rs alpha)${NL}${rev}${NL}${dn}"
run_gate "H3"
none "H3 missing, resolved, resolved (explicitly resolved)"

# ---- the rest of the clearing table (A37b) ------------------------------------------
# T1: open, missing, resolved -> no
gate_rounds "$(op alpha)" "" "$(rs alpha)"
run_gate "T1"; none "T1 open, missing, resolved"
# T2: open, missing, open -> no (re-flagged; the normal comparison watches it)
gate_rounds "$(op alpha)" "" "$(op alpha)"
run_gate "T2"; none "T2 open, missing, open"
# T3: open, missing, open, open -> no
gate_rounds "$(op alpha)" "" "$(op alpha)" "$(op alpha)"
run_gate "T3"; none "T3 open, missing, open, open"
# T4: open, missing, open, missing -> a new gap: one line, round 4 (the round-2 gap is cleared)
gate_rounds "$(op alpha)" "" "$(op alpha)" ""
run_gate "T4"; only_one "T4 open, missing, open, missing" alpha 4
# T5: open, missing, missing -> round 2, once; round 3 is no gap
gate_rounds "$(op alpha)" "" ""
run_gate "T5"; only_one "T5 open, missing, missing" alpha 2
if printf '%s' "$rr_out" | LC_ALL=C grep -aq 'round 3'; then
  fail "S254/T5 — round 2 left nothing open, so round 3 is no gap, and the output names round 3: $(printf '%s' "$rr_out" | LC_ALL=C tr '\n' '|')"
fi
# T6: open, missing, missing, open -> no (re-flagged after two rounds)
gate_rounds "$(op alpha)" "" "" "$(op alpha)"
run_gate "T6"; none "T6 open, missing, missing, open"
# T7: missing, missing, open (open in the last round only) -> no
gate_rounds "" "" "$(op alpha)"
run_gate "T7"; none "T7 open in the last round only"

test_done
