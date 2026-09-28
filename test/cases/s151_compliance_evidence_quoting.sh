#!/usr/bin/env bash
# S151 — Marker-shaped text that is quoted, or isn't a real HTML comment,
# is not evidence (issue #308).
# Covers: F34

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/compliance-evidence.sh"
[ -x "$script" ] || { fail "S151 — compliance-evidence.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# Shared fixture constants + shape helpers — issue #308, extracted so S150
# and S151 can't drift on the --json field list / --jq expression. See
# test/compliance-evidence-fixture.sh.
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"

# Q12 (AC3 — "the whole existing s150 file, expectations unedited"): not
# re-executed here. It's a separate file, run separately by test/run.sh,
# specifically so this regression proof (S150 stays green with zero
# expectation edits — only the shared CALL_*_ARGS/extraction changed) is
# observable on its own, per QA's §4 rationale for splitting S150/S151 in
# the first place. Folding it into this file would defeat that.
#
# Cross-cutting on every arm below: assert_table_shape (AC6: six rows,
# closed four-value status vocabulary, non-empty Evidence cells). The
# read-only/no-write-path assertion (AC5) is a static source-level check,
# already asserted once in S150 (which covers this script's whole
# source) — not repeated per arm here, same call S150 already made for
# its own many arms.

# =========================================================================
# AC1 — quoted occurrences are not evidence (red before the fix).
# =========================================================================

# Q1 — PR body: one sentence carrying all four model-record markers and a
# pre-merge-review:done marker, each in single backticks; no unquoted
# marker anywhere.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\tConvention: `<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->` `<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->` `<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->` `<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->` and `<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->` are the five markers this workflow uses.\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q1="$(cat "$FAKEGH_OUT")"
output_q1="$(PATH="$fakebin_q1:$PATH" "$script" 279)"
assert_table_shape "S151 Q1" "$output_q1"
[ "$(row_status "$output_q1" 1)" = "not-evidenced" ] || fail "S151 Q1 — expected gate 1 not-evidenced (all backticked), got '$(row_status "$output_q1" 1)'"
[ "$(row_status "$output_q1" 2)" = "not-evidenced" ] || fail "S151 Q1 — expected gate 2 not-evidenced (all backticked), got '$(row_status "$output_q1" 2)'"
[ "$(row_status "$output_q1" 3)" = "not-evidenced" ] || fail "S151 Q1 — expected gate 3 not-evidenced (all backticked), got '$(row_status "$output_q1" 3)'"

# Q2 — PR comment: a three-backtick fenced block containing the same five
# markers.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t```\001<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\001<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\001<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\001<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\001```\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q2="$(cat "$FAKEGH_OUT")"
output_q2="$(PATH="$fakebin_q2:$PATH" "$script" 279)"
assert_table_shape "S151 Q2" "$output_q2"
[ "$(row_status "$output_q2" 1)" = "not-evidenced" ] || fail "S151 Q2 — expected gate 1 not-evidenced (fenced), got '$(row_status "$output_q2" 1)'"
[ "$(row_status "$output_q2" 2)" = "not-evidenced" ] || fail "S151 Q2 — expected gate 2 not-evidenced (fenced), got '$(row_status "$output_q2" 2)'"
[ "$(row_status "$output_q2" 3)" = "not-evidenced" ] || fail "S151 Q2 — expected gate 3 not-evidenced (fenced), got '$(row_status "$output_q2" 3)'"

# Q3 — closing-issue comment: GitHub quote-reply shape, no escaping. The
# arm that justifies the transport change; it cannot pass without it.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TITLE\tCloses #265\n'
    printf 'TEXT\t\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t> <!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q3="$(cat "$FAKEGH_OUT")"
output_q3="$(PATH="$fakebin_q3:$PATH" "$script" 279)"
assert_table_shape "S151 Q3" "$output_q3"
[ "$(row_status "$output_q3" 3)" = "not-evidenced" ] || fail "S151 Q3 — expected gate 3 not-evidenced (blockquoted), got '$(row_status "$output_q3" 3)'"

# Q4 — backticked markers in a closing issue comment, PR itself clean:
# proves stripping runs on call C too, not only call A.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TITLE\tCloses #265\n'
    printf 'TEXT\t\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t`<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->` `<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->` `<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->` `<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->`\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q4="$(cat "$FAKEGH_OUT")"
output_q4="$(PATH="$fakebin_q4:$PATH" "$script" 279)"
assert_table_shape "S151 Q4" "$output_q4"
[ "$(row_status "$output_q4" 1)" = "not-evidenced" ] || fail "S151 Q4 — expected gate 1 not-evidenced (backticked in closing issue), got '$(row_status "$output_q4" 1)'"
[ "$(row_status "$output_q4" 2)" = "not-evidenced" ] || fail "S151 Q4 — expected gate 2 not-evidenced (backticked in closing issue), got '$(row_status "$output_q4" 2)'"

# Q13 — D5 repro: a four-backtick wrapper whose content is a three-backtick
# fence around a pre-merge-review:done marker.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t````\001```\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\001```\001````\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q13="$(cat "$FAKEGH_OUT")"
output_q13="$(PATH="$fakebin_q13:$PATH" "$script" 279)"
assert_table_shape "S151 Q13" "$output_q13"
[ "$(row_status "$output_q13" 3)" = "not-evidenced" ] || fail "S151 Q13 (D5 repro) — expected gate 3 not-evidenced (outer 4-backtick wrapper around inner fence), got '$(row_status "$output_q13" 3)'"

# Q13b — the ~~~-wrapped variant of D5.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t~~~\001```\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\001```\001~~~\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q13b="$(cat "$FAKEGH_OUT")"
output_q13b="$(PATH="$fakebin_q13b:$PATH" "$script" 279)"
assert_table_shape "S151 Q13b" "$output_q13b"
[ "$(row_status "$output_q13b" 3)" = "not-evidenced" ] || fail "S151 Q13b (D5 ~~~ variant) — expected gate 3 not-evidenced, got '$(row_status "$output_q13b" 3)'"

# Q13c — D10 repro (Architect's follow-up): a bare ``` fence whose second
# line is ```text (an info string on what would otherwise be a closing
# fence), marker on the third line, closed by ```. Red against today's
# code, red against Architect's original awk, AND red against QA's
# char/length-only fix — that last property is why this arm has to exist
# separately from Q13/Q13b.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t```\001```text\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\001```\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q13c="$(cat "$FAKEGH_OUT")"
output_q13c="$(PATH="$fakebin_q13c:$PATH" "$script" 279)"
assert_table_shape "S151 Q13c" "$output_q13c"
[ "$(row_status "$output_q13c" 3)" = "not-evidenced" ] || fail "S151 Q13c (D10 repro) — expected gate 3 not-evidenced ('\`\`\`text' is content, not a valid close), got '$(row_status "$output_q13c" 3)'"

# =========================================================================
# AC2 — self-echo (red before the fix).
# =========================================================================

# Q5 — two runs off one base fixture; run 2 adds a TEXT line containing
# run 1's exact rendered table. Outputs must be byte-identical: diffed,
# never a hand-written expectation.
#
# Base fixture is deliberately marker-less (D11/F4, review round 1): a
# base that already carries a real, live marker is `evidenced` in run 1
# regardless of whether the fix helps, so pasting the table back can only
# leave it `evidenced` too — the arm can never discriminate. The real
# self-echo vector is the opposite base: NO real marker anywhere, so run
# 1 is `not-evidenced`, and run 1's own rendered Evidence cell for gate 3
# ("no `pre-merge-review:done` marker found on PR #279…") mentions the
# marker text itself, backticked, purely as part of that sentence — never
# a real HTML comment. Pasting that sentence into run 2's body is what
# actually exercises whether quoted, marker-shaped prose can fake its way
# to a different verdict on the next run.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q5_1="$(cat "$FAKEGH_OUT")"
output_q5_1="$(PATH="$fakebin_q5_1:$PATH" "$script" 279)"
assert_table_shape "S151 Q5 run1" "$output_q5_1"
[ "$(row_status "$output_q5_1" 3)" = "not-evidenced" ] || fail "S151 Q5 run1 — expected gate 3 not-evidenced for the marker-less base, got '$(row_status "$output_q5_1" 3)'"

# Sentinel-encode run 1's own rendered output and hand it to run 2's fake
# gh via a fixture file (never embedded as a shell-quoted literal — the
# collector's own header row contains an apostrophe, "Ties' explicit
# merge confirmation", which would otherwise have to be hand-escaped).
q5_echo_file="$SANDBOX/q5-echo.txt"
printf '%s' "$output_q5_1" | tr '\n' '\001' > "$q5_echo_file"
run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF2
case "\$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t'
    cat "$q5_echo_file"
    printf '\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF2
fakebin_q5_2="$(cat "$FAKEGH_OUT")"
output_q5_2="$(PATH="$fakebin_q5_2:$PATH" "$script" 279)"
assert_table_shape "S151 Q5 run2" "$output_q5_2"
[ "$(row_status "$output_q5_2" 3)" = "not-evidenced" ] || fail "S151 Q5 run2 (AC2 self-echo) — pasting run 1's own rendered Evidence text (a quoted mention of the marker, never a real one) into the PR body must not flip gate 3 away from not-evidenced, got '$(row_status "$output_q5_2" 3)'"
[ "$output_q5_1" = "$output_q5_2" ] || {
  fail "S151 Q5 (AC2 self-echo) — pasting run 1's own rendered table into the PR changed run 2's output:"
  diff <(printf '%s\n' "$output_q5_1") <(printf '%s\n' "$output_q5_2") >&2 || true
}

# =========================================================================
# AC3 — real markers keep evidencing (green before and after; a red here
# is a defect in the fix, not progress).
# =========================================================================

# Q6 — a body shaped like this issue's real Discovery comment: balanced
# code spans, prose, and a live marker ending a line that also carries
# text.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\tRan on `claude-opus-5` at `high` effort using `sha=` conventions and `gsub("\\n";" ")`; recorded here: <!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q6="$(cat "$FAKEGH_OUT")"
output_q6="$(PATH="$fakebin_q6:$PATH" "$script" 279)"
assert_table_shape "S151 Q6" "$output_q6"
[ "$(row_status "$output_q6" 3)" = "evidenced" ] || fail "S151 Q6 — expected gate 3 evidenced (marker inline with balanced code spans and prose), got '$(row_status "$output_q6" 3)'"

# Q7 — Q6 plus one stray unmatched backtick earlier on the marker's line.
# Still evidenced: CommonMark's "unmatched run is literal" rule. The
# highest-value regression arm in the set.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t` Ran on `claude-opus-5` at `high` effort using `sha=` conventions and `gsub("\\n";" ")`; recorded here: <!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q7="$(cat "$FAKEGH_OUT")"
output_q7="$(PATH="$fakebin_q7:$PATH" "$script" 279)"
assert_table_shape "S151 Q7" "$output_q7"
[ "$(row_status "$output_q7" 3)" = "evidenced" ] || fail "S151 Q7 (odd-tick trap) — expected gate 3 still evidenced with a stray unmatched backtick earlier on the line, got '$(row_status "$output_q7" 3)'"

# Q8 — real marker inside a Markdown table cell on a row that also
# carries a backticked value: pipes and adjacent spans are not enclosure.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t| `claude-opus-5` | <!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 --> |\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q8="$(cat "$FAKEGH_OUT")"
output_q8="$(PATH="$fakebin_q8:$PATH" "$script" 279)"
assert_table_shape "S151 Q8" "$output_q8"
[ "$(row_status "$output_q8" 3)" = "evidenced" ] || fail "S151 Q8 — expected gate 3 evidenced (marker in a table cell alongside a backticked value), got '$(row_status "$output_q8" 3)'"

# Q9 — fence isolation: body 1 opens a fence and never closes it; body 2
# (a separate PR comment) carries a real marker. Fence state must not
# cross bodies.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t```\001never closes in this body\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q9="$(cat "$FAKEGH_OUT")"
output_q9="$(PATH="$fakebin_q9:$PATH" "$script" 279)"
assert_table_shape "S151 Q9" "$output_q9"
[ "$(row_status "$output_q9" 3)" = "evidenced" ] || fail "S151 Q9 (fence isolation) — expected gate 3 evidenced for a separate body's marker after an unrelated body left a fence open, got '$(row_status "$output_q9" 3)'"

# Q10 — D6 repro: an even fence-ish demonstration, then a real marker
# after it.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t````\001```\001````\001some text\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q10="$(cat "$FAKEGH_OUT")"
output_q10="$(PATH="$fakebin_q10:$PATH" "$script" 279)"
assert_table_shape "S151 Q10" "$output_q10"
[ "$(row_status "$output_q10" 3)" = "evidenced" ] || fail "S151 Q10 (D6 repro) — expected gate 3 evidenced after an even fence-ish demonstration, got '$(row_status "$output_q10" 3)'"

# Q11 — D7 repro: a four-space-indented fence-ish line, then a real
# marker. Over-indented is not a fence (CommonMark's 3-space cap) and
# must not swallow the body.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t    ```\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q11="$(cat "$FAKEGH_OUT")"
output_q11="$(PATH="$fakebin_q11:$PATH" "$script" 279)"
assert_table_shape "S151 Q11" "$output_q11"
[ "$(row_status "$output_q11" 3)" = "evidenced" ] || fail "S151 Q11 (D7 repro) — expected gate 3 evidenced after a 4-space-indented fence-ish line, got '$(row_status "$output_q11" 3)'"

# =========================================================================
# AC4 — wording (Q14 red before the fix).
# =========================================================================

# Q14 — Q1's fixture: not-evidenced AND the Evidence cell must say quoted
# occurrences were seen and ignored, not read as a bare "no marker found".
evidence_q14="$(row_evidence "$output_q1" 1)"
case "$evidence_q14" in
  # Substring guaranteed to survive cell()'s 300-char truncation on this
  # fixture (4 missing stages makes the full wording long enough to be
  # cut, with "…" appended, per cell()'s existing contract — the tail
  # end of the suffix isn't asserted here for that reason).
  *"marker-shaped text matching this gate does appear on PR #279"*) : ;;
  *) fail "S151 Q14 (AC4 wording) — gate 1's Evidence cell doesn't say quoted occurrences were seen and ignored: $evidence_q14" ;;
esac
bare_q14='no model-record marker found for stage(s) Discovery, Planning, Test, Implementation, searched in PR #279'"'"'s body/comments and its closing issue(s)'
[ "$evidence_q14" != "$bare_q14" ] || fail "S151 Q14 (AC4 wording) — gate 1's Evidence cell reads as a bare 'no marker found', with no mention of the quoted occurrences that do exist"

# =========================================================================
# AC7 / D8 — bare prose is not a marker at all, and quoted_suffix() must
# not claim "quoted" about text that was never quoted in the first place.
# =========================================================================

# Q15 — D8 guard: bare prose, no delimiters, not quoted anywhere. Must be
# not-evidenced AND the quoted-wording suffix must be absent (the corpus
# contains no quoted marker at all — saying otherwise would be a new
# falsehood of the same class AC1 exists to remove).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\twe should add a model-record: stage=Test marker\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q15="$(cat "$FAKEGH_OUT")"
output_q15="$(PATH="$fakebin_q15:$PATH" "$script" 279)"
assert_table_shape "S151 Q15" "$output_q15"
[ "$(row_status "$output_q15" 1)" = "not-evidenced" ] || fail "S151 Q15 (D8 guard) — expected gate 1 not-evidenced for bare prose, got '$(row_status "$output_q15" 1)'"
evidence_q15="$(row_evidence "$output_q15" 1)"
case "$evidence_q15" in
  # Same prefix Q14 asserts on (not the "quoted illustration"/"not counted
  # as live evidence" tail wording): the fixture's 300-char cell()
  # truncation always removes that tail, so asserting its absence here
  # would be vacuous — it can never appear regardless of whether D8's
  # anchoring bug is present. The prefix below is what quoted_suffix()
  # emits from an UNANCHORED ere (D8's exact failure mode: a loose,
  # non-"<!--"-anchored ERE matches this bare-prose corpus and wrongly
  # appends the suffix), so asserting its absence is what actually
  # exercises the anchoring fix.
  *"marker-shaped text matching this gate does appear on PR #279"*)
    fail "S151 Q15 (D8 guard) — gate 1's Evidence cell wrongly claims quoted text was seen, but the corpus has none (bare prose only, no delimiters): $evidence_q15" ;;
esac

# =========================================================================
# AC5 — errors resolve toward silence, and the documented fail-open.
# =========================================================================

# Q16 — a fence opened and never closed, marker after it: not-evidenced,
# not evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t```\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q16="$(cat "$FAKEGH_OUT")"
output_q16="$(PATH="$fakebin_q16:$PATH" "$script" 279)"
assert_table_shape "S151 Q16" "$output_q16"
[ "$(row_status "$output_q16" 3)" = "not-evidenced" ] || fail "S151 Q16 (AC5 unclosed fence) — expected gate 3 not-evidenced, got '$(row_status "$output_q16" 3)'"

# Q17 — quoted-only markers plus a failed gh issue view: indeterminate
# wins over AC4's wording (incompleteness outranks quoting).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TITLE\tCloses #265\n'
    printf 'TEXT\t`<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->`\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_q17="$(cat "$FAKEGH_OUT")"
output_q17="$(PATH="$fakebin_q17:$PATH" "$script" 279 2>/dev/null)"
assert_table_shape "S151 Q17" "$output_q17"
[ "$(row_status "$output_q17" 3)" = "indeterminate" ] || fail "S151 Q17 (AC5 precedence) — expected gate 3 indeterminate (failed issue lookup outranks quoting), got '$(row_status "$output_q17" 3)'"

# Q18 — the documented failure, asserted on purpose: a marker inside a
# four-space-indented code block (CommonMark), otherwise a clean PR.
# Non-goal 1 promises this shape fails open (evidenced); this arm exists
# so a later half-fix to indented blocks is a visible, reviewed status
# change rather than a silent one. The fix for this arm, if ever taken,
# is to delete it and move the PRD.md debt row — not to "correct" the
# expectation in place.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t    <!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q18="$(cat "$FAKEGH_OUT")"
output_q18="$(PATH="$fakebin_q18:$PATH" "$script" 279)"
assert_table_shape "S151 Q18" "$output_q18"
[ "$(row_status "$output_q18" 3)" = "evidenced" ] || fail "S151 Q18 (AC5 documented fail-open, indented code block) — expected gate 3 evidenced (accepted debt, PRD.md), got '$(row_status "$output_q18" 3)'"

# Q18b — same fail-open family: an HTML <pre>/<code> block.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<pre><code>\001<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\001</code></pre>\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q18b="$(cat "$FAKEGH_OUT")"
output_q18b="$(PATH="$fakebin_q18b:$PATH" "$script" 279)"
assert_table_shape "S151 Q18b" "$output_q18b"
[ "$(row_status "$output_q18b" 3)" = "evidenced" ] || fail "S151 Q18b (AC5 documented fail-open, <pre>/<code>) — expected gate 3 evidenced (accepted debt, PRD.md), got '$(row_status "$output_q18b" 3)'"

# =========================================================================
# AC7 — literal syntax must be a real HTML comment (Q19 red before the
# fix).
# =========================================================================

# Q19 — bare prose, nothing else: gate 1 not-evidenced, not
# indeterminate/malformed.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\twe should add a model-record: stage=Test marker\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q19="$(cat "$FAKEGH_OUT")"
output_q19="$(PATH="$fakebin_q19:$PATH" "$script" 279)"
assert_table_shape "S151 Q19" "$output_q19"
[ "$(row_status "$output_q19" 1)" = "not-evidenced" ] || fail "S151 Q19 (AC7) — expected gate 1 not-evidenced for bare prose, got '$(row_status "$output_q19" 1)'"

# Q19b — a sentence mentioning pre-merge-review:done with no delimiters:
# gate 3 not-evidenced, not indeterminate.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\twe already ran pre-merge-review:done on this PR\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q19b="$(cat "$FAKEGH_OUT")"
output_q19b="$(PATH="$fakebin_q19b:$PATH" "$script" 279)"
assert_table_shape "S151 Q19b" "$output_q19b"
[ "$(row_status "$output_q19b" 3)" = "not-evidenced" ] || fail "S151 Q19b (AC7) — expected gate 3 not-evidenced for bare prose, got '$(row_status "$output_q19b" 3)'"

# Q20 — unquoted value, real delimiters: still indeterminate. The
# anchoring must not cost the malformed diagnostic. (Q20b — the
# equivalent gate-3 case — already exists in S150 (AC8a); not duplicated
# here per QA's own note, just relied on as unchanged.)
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Test model=sonnet -->\n'
    exit 0 ;;
  __CALL_A_COMMENTS__)
    printf ''
    exit 0 ;;
  __CALL_A_REVIEWS__)
    printf ''
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_q20="$(cat "$FAKEGH_OUT")"
output_q20="$(PATH="$fakebin_q20:$PATH" "$script" 279)"
assert_table_shape "S151 Q20" "$output_q20"
[ "$(row_status "$output_q20" 1)" = "indeterminate" ] || fail "S151 Q20 (AC7 malformed preserved) — expected gate 1 indeterminate for an unquoted value inside real delimiters, got '$(row_status "$output_q20" 1)'"

# =========================================================================
# Transport — new surface, all green after the fix. Exercised directly
# against the real CALL_A_JQ expression and live_text(), both extracted
# verbatim from compliance-evidence.sh (never retyped), since a fake gh
# bypasses the real jq call entirely and so can't exercise the sentinel
# transport by itself.
# =========================================================================

if ! command -v jq >/dev/null 2>&1; then
  # Loud, per s44's convention (a comment on that arm calls this out
  # explicitly): a silent skip would mean the only coverage of the
  # sentinel transport disappears behind one easily-missed stderr line on
  # any runner without jq, with the suite still reporting green. Fail
  # instead, naming exactly what's missing and why.
  fail "S151 — jq not installed; cannot run Q21-Q23 (transport-level checks against the real CALL_A_JQ expression and live_text())"
else
  call_a_jq_line="$(grep '^CALL_A_JQ=' "$script")"
  eval "$call_a_jq_line"
  # shellcheck disable=SC2317  # invoked below via eval'd extraction, not a dead branch
  eval "$(awk '/^live_text\(\) \{/,/^}/' "$script")"

  # Q21 — CRLF body: an unrelated demo fence with a trailing \r on its
  # open and close lines, and a real marker (also trailing \r) after it
  # closes. Guards the gsub("\r";"") half of the transport change: with
  # \r left in, the close-fence branch's `rest ~ /^[ \t]*$/` check (D10)
  # never matches, the fence never closes, and the marker after it gets
  # swallowed — a failure mode that only shows up against real GitHub
  # data (which is CRLF) and never in a fixture that forgets to add \r.
  q21_body=$'```\r\nsome demo content\r\n```\r\n<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\r'
  q21_json="$(jq -n --arg body "$q21_body" '{body:$body}')"
  q21_out="$(printf '%s' "$q21_json" | jq -r "$CALL_A_JQ")"
  q21_raw_line="$(printf '%s' "$q21_out" | grep '^TEXT' | cut -f2-)"
  q21_raw_body="$(printf '%s' "$q21_raw_line" | tr '\001' '\n')"
  case "$q21_raw_body" in
    *$'\r'*) fail "S151 Q21 (transport) — a \\r survived the jq gsub; raw body still contains one" ;;
  esac
  q21_live="$(live_text "$q21_raw_body")"
  grep -q 'pre-merge-review:done' <<<"$q21_live" || fail "S151 Q21 (transport, D10 coupling) — the CRLF fence line must still close, and the marker after it must stay live"

  # Q22 — a literal U+0001 already present in the body, adjacent to
  # marker-shaped text: the neutralising first gsub must turn it into a
  # space, not let it manufacture a fake line break downstream.
  q22_body=$'text with a stray \001 byte then <!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->'
  q22_json="$(jq -n --arg body "$q22_body" '{body:$body}')"
  q22_out="$(printf '%s' "$q22_json" | jq -r "$CALL_A_JQ")"
  q22_raw_line="$(printf '%s' "$q22_out" | grep '^TEXT' | cut -f2-)"
  q22_raw_body="$(printf '%s' "$q22_raw_line" | tr '\001' '\n')"
  q22_line_count="$(printf '%s\n' "$q22_raw_body" | wc -l | tr -d ' ')"
  [ "$q22_line_count" = "1" ] || fail "S151 Q22 (transport) — a literal U+0001 in the body forged a line break: expected 1 line, got $q22_line_count"
  q22_live="$(live_text "$q22_raw_body")"
  grep -q 'pre-merge-review:done' <<<"$q22_live" || fail "S151 Q22 (transport) — the marker must stay live; the stray byte must not manufacture blockquote/fence structure"

  # Q23 — a genuinely multi-line body, marker on its third line: the
  # sentinel round-trip works end to end, exercised rather than merely
  # incidentally covered.
  q23_body=$'first line\nsecond line\n<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->'
  q23_json="$(jq -n --arg body "$q23_body" '{body:$body}')"
  q23_out="$(printf '%s' "$q23_json" | jq -r "$CALL_A_JQ")"
  q23_raw_line="$(printf '%s' "$q23_out" | grep '^TEXT' | cut -f2-)"
  q23_raw_body="$(printf '%s' "$q23_raw_line" | tr '\001' '\n')"
  q23_line_count="$(printf '%s\n' "$q23_raw_body" | wc -l | tr -d ' ')"
  [ "$q23_line_count" = "3" ] || fail "S151 Q23 (transport) — expected 3 real lines after the sentinel round-trip, got $q23_line_count"
  q23_live="$(live_text "$q23_raw_body")"
  grep -q 'pre-merge-review:done' <<<"$q23_live" || fail "S151 Q23 (transport) — the marker on the third line must stay live end to end"
fi

test_done
