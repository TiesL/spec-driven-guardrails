#!/usr/bin/env bash
# S216 — review-rounds.sh counts Review rounds and reports Planning markers after each.
# Covers: F42
#
# Issue #410, AC4 (Architect A28; round definition per A37, PR reviews
# included). Seam: the real script against a recording fake gh (REST data
# with real timestamps). Red now: the script does not exist.
#
# Assumption decided here (A28 does not spell it out): a Planning marker is
# "after" the latest Review round that precedes it, so it is reported once,
# against that round. Rounds are numbered in time order across PR comments
# and PR reviews. One well-formed Review marker in a comment or review body
# is one round.
#
# Mutations that turn this red (tag in the message):
#  zero        make zero rounds print nothing, or exit 1
#  count       count every model-record marker, not only Review; or count malformed Review markers
#  time-order  number the rounds in file order, not time order (review earlier than comment)
#  reviews     read PR comments only, not PR reviews
#  planning    report Planning against every earlier round, or only on the issue, or drop the issue side
#  quoted      count a Review marker in a fenced/tilde/span/blockquote example; or a quoted Planning
#  severity    drop the severity line
#  exit        exit non-zero when rounds exist

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

RR_SCRIPT="$TEST_REPO_ROOT/review-rounds.sh"
[ -x "$RR_SCRIPT" ] || { fail "S216 — review-rounds.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S216 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out=""
rr_status=0 # set by rr_run
NL=$'\n'
BT='`'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z T3=2026-10-03T10:00:00Z
T4=2026-10-04T10:00:00Z T5=2026-10-05T10:00:00Z
rev="$(rr_review)"
pln="$(rr_planning)"

# ---- zero rounds: honest zero, exit 0, no round lines ----------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "$(rr_stage Test)" "$T2" "$(rr_stage Implementation)" "$T3" "just a comment"
rr_run "$RR_PR" "$RR_ISSUE"
[ "$rr_status" -eq 0 ] || fail "S216/zero — exit $rr_status with zero rounds, expected 0"
[ "$(rr_lines '^review-rounds: 0$')" = "review-rounds: 0" ] || fail "S216/zero — no 'review-rounds: 0' line, got: $rr_out"
[ -z "$(rr_lines '^review-round: ')" ] || fail "S216/zero — a review-round line was printed for zero rounds: $rr_out"
[ -z "$(rr_lines '^planning-after: ')" ] || fail "S216/zero — a planning-after line was printed with no round: $rr_out"
[ -n "$(rr_lines_i 'severity.*not machine-readable')" ] || fail "S216/severity — no line saying severity is not machine-readable (zero rounds)"

# ---- three rounds: a PR REVIEW is the earliest, listed LAST in its own file;
#      Planning on the issue between round 1 and 2, on the PR after round 3, and
#      one BEFORE every round (the original Planning, never reported). ----------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T2" "round two:${NL}${rev}" \
  "$T4" "round three:${NL}${rev}" \
  "$T5" "Redesign done, no change needed.${NL}${pln}"
rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at \
  "$T1" "request changes:${NL}${rev}"
rr_json "$FAKE_GH_DATA/comments-$RR_ISSUE.json" created_at \
  "2026-09-30T09:00:00Z" "$pln" \
  "$T3" "back to the Architect:${NL}${pln}"
rr_run "$RR_PR" "$RR_ISSUE"
[ "$rr_status" -eq 0 ] || fail "S216/exit — exit $rr_status, expected 0"
[ "$(rr_lines '^review-round: ')" = "review-round: 1 at=$T1${NL}review-round: 2 at=$T2${NL}review-round: 3 at=$T4" ] \
  || fail "S216/time-order — rounds are not 1..3 in time order across comments and reviews (review at $T1 first), got: $(rr_lines '^review-round: ' | tr '\n' '|')"
[ "$(rr_lines '^review-rounds: ')" = "review-rounds: 3" ] || fail "S216/count — summary is not 'review-rounds: 3': $rr_out"
[ "$(rr_lines '^planning-after: ')" = "planning-after: 2${NL}planning-after: 3" ] \
  || fail "S216/planning — expected exactly 'planning-after: 2' (issue, $T3) and 'planning-after: 3' (PR, $T5); the Planning before round 1 is not reported; got: $(rr_lines '^planning-after: ' | tr '\n' '|')"
[ -n "$(rr_lines_i 'severity.*not machine-readable')" ] || fail "S216/severity — no line saying severity is not machine-readable"
# the summary comes after the round lines
first_sum="$(printf '%s\n' "$rr_out" | grep -n '^review-rounds: ' | head -1 | cut -d: -f1)"
last_round="$(printf '%s\n' "$rr_out" | grep -n '^review-round: ' | tail -1 | cut -d: -f1)"
[ -n "$first_sum" ] && [ -n "$last_round" ] && [ "$first_sum" -gt "$last_round" ] \
  || fail "S216/count — the summary line is not after the last round line"
# deterministic
first="$rr_out"
rr_run "$RR_PR" "$RR_ISSUE"
[ "$rr_out" = "$first" ] || fail "S216/exit — two runs on the same data printed different output"

# ---- without the issue argument the issue side is not read -----------------
: > "$RR_LOG"
rr_run "$RR_PR"
[ "$rr_status" -eq 0 ] || fail "S216/planning — exit $rr_status without the issue argument"
[ "$(rr_lines '^planning-after: ')" = "planning-after: 3" ] \
  || fail "S216/planning — without the issue only the PR's Planning ($T5, after round 3) may be reported, got: $(rr_lines '^planning-after: ' | tr '\n' '|')"
grep -q "issues/$RR_ISSUE/" "$RR_LOG" && fail "S216/planning — the issue's comments were fetched although no issue was given"

# ---- only well-formed Review markers are rounds ------------------------------
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
  "$T1" "$(rr_stage Discovery)" \
  "$T2" "$(rr_stage Implementation)" \
  "$T3" '<!-- model-record: stage=Review model="x" effort="high" floor-basis="no closing' \
  "$T4" '<!-- model-record: stage="Review" model="x" effort="high" floor-basis="quoted stage" -->' \
  "$T5" "the one real round${NL}${rev}"
rr_run "$RR_PR" "$RR_ISSUE"
[ "$(rr_lines '^review-rounds: ')" = "review-rounds: 1" ] \
  || fail "S216/count — only the one well-formed Review marker is a round (other stages, an unclosed marker and a quoted stage= are not), got: $(rr_lines '^review-rounds?: ' | tr '\n' '|')"
[ "$(rr_lines '^review-round: ')" = "review-round: 1 at=$T5" ] || fail "S216/count — round 1 is not the real marker's comment ($T5): $(rr_lines '^review-round: ')"

# ---- quoted example markers are not rounds and not Planning ------------------
q_fence="Example:${NL}\`\`\`${NL}${rev}${NL}\`\`\`"
q_tilde="Example:${NL}~~~${NL}${rev}${NL}~~~"
q_span="The format is ${BT}${rev}${BT}, as in the skill."
q_block="> Reviewer wrote:${NL}> ${rev}"
for form in fence tilde span block; do
  case "$form" in fence) q="$q_fence" ;; tilde) q="$q_tilde" ;; span) q="$q_span" ;; block) q="$q_block" ;; esac
  qp="${q//$rev/$pln}"
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
    "$T1" "real round${NL}${rev}" \
    "$T2" "$q" \
    "$T3" "$qp" \
    "$T4" "real round with an example inside${NL}${rev}${NL}${q}"
  rr_run "$RR_PR" "$RR_ISSUE"
  [ "$(rr_lines '^review-rounds: ')" = "review-rounds: 2" ] \
    || fail "S216/quoted — a quoted ($form) example Review marker was counted (two real rounds expected), got: $(rr_lines '^review-rounds: ')"
  [ -z "$(rr_lines '^planning-after: ')" ] \
    || fail "S216/quoted — a quoted ($form) example Planning marker was reported as Planning after a round: $(rr_lines '^planning-after: ')"
done

test_done
