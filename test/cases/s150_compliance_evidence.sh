#!/usr/bin/env bash
# S150 — The compliance-evidence collector reports what the artifacts
# actually show (issue #296).
# Covers: F34

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/compliance-evidence.sh"
[ -x "$script" ] || { fail "S150 — compliance-evidence.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# Shared fixture constants + shape helpers (CALL_*_ARGS, run_build_fake_gh,
# GATE1-6, assert_table_shape, row_status, row_evidence) — issue #308:
# extracted into one sourced file, also used by S151
# (test/cases/s151_compliance_evidence_quoting.sh), so a drift in
# compliance-evidence.sh's --json field list or --jq expression is a
# one-line fix there instead of a synchronized edit across both test
# files.
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"

# =========================================================================
# AC1 — reproduces the decided worked example (PR #279 / issue #265),
# referentially: each row cites the same underlying artifact the
# hand-written PRD §6 example cites.
#
# Fixture header: a recording of PR #279's real `gh pr view` / `gh pr
# checks` / `gh issue view` answers, as of 2026-09-26. Round-1's stale
# Review marker's exception text is paraphrased here to drop an
# apostrophe the live text has (single-quoted printf arguments below
# can't survive one) — its content, not its exact wording, is what every
# assertion here depends on.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="the fork session inherits its parent model; no other model was available to run this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=472bc8f574c4aea3fc58161d1924b7b05329172f -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac1="$(cat "$FAKEGH_OUT")"

# shellcheck disable=SC2016  # the backticks below are literal Markdown, not command substitution — single-quoted deliberately
expected_ac1='| Gate | Status | Evidence |
| --- | --- | --- |
| Per-stage model/effort recorded (Discovery, Planning, Test, Implementation) | evidenced | `model-record` markers on PR #279 for Discovery, Planning, Test, Implementation (all `claude-sonnet-5`) |
| Review used a different or at-least-as-capable model, or carries an explicit exception | evidenced | latest `stage=Review` marker on PR #279 carries `same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review"` |
| Quality review before merge, with findings in the PR | evidenced | `<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->` on PR #279, sha equals `headRefOid` (an earlier marker for `472bc8f574c4aea3fc58161d1924b7b05329172f` is stale) |
| CI green | evidenced | check `check`: `bucket=pass`, `state=SUCCESS` |
| Traceability link 3 (PR ↔ issue) | evidenced | `closingIssuesReferences` on PR #279 = [#265] |
| Ties'"'"' explicit merge confirmation | unverifiable-from-artifacts | not derivable from artifacts; A2 confirmation is conversational (PR merged by @TiesL at 2026-09-20T17:31:36Z, which is not the confirmation) |'

output_ac1="$(PATH="$fakebin_ac1:$PATH" "$script" 279)"
status_ac1=$?
[ "$status_ac1" -eq 0 ] || fail "S150 AC1 — expected exit 0, got $status_ac1"
[ "$output_ac1" = "$expected_ac1" ] || {
  fail "S150 AC1 — output doesn't match the worked example (referential identity, PR #279/#265):"
  diff <(printf '%s\n' "$expected_ac1") <(printf '%s\n' "$output_ac1") >&2 || true
}
assert_table_shape "S150 AC1" "$output_ac1"

# Determinism (AC6): the same fixture run twice must be byte-identical —
# catches a collector that stamps a collection timestamp into the output.
output_ac1_again="$(PATH="$fakebin_ac1:$PATH" "$script" 279)"
[ "$output_ac1" = "$output_ac1_again" ] || fail "S150 AC6 — two runs against the same fixture produced different output (not deterministic)"

# =========================================================================
# A3 (meta-review, epic #295) — gate 1's non-uniform-model branch, which
# every fixture above skips (all nineteen original arms use one model
# across all four stages). This is not a hypothetical: every real
# multi-agent pipeline PR — including this very PR — records Opus for
# Discovery/Planning/Test and Sonnet for Implementation, so the
# "else" branch of gate_stage_models() (per-stage summary, as opposed to
# "all `<model>`") is the branch every future pipeline PR actually takes.
# It previously rendered with a stray leading space right after the "("
# (`summary` accumulates as " Discovery=`...`,  Planning=`...`, ..." and
# only its trailing comma was ever trimmed) — asserted here as an exact
# string match on the Evidence cell, not just a non-empty check, so a
# regression of that space is caught.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-opus-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-opus-5" effort="high" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-opus-5" effort="high" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="high" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="high" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_mixedmodel="$(cat "$FAKEGH_OUT")"
output_mixedmodel="$(PATH="$fakebin_mixedmodel:$PATH" "$script" 279)"
status_mixedmodel=$?
[ "$status_mixedmodel" -eq 0 ] || fail "S150 A3 mixed-model — expected exit 0, got $status_mixedmodel"
assert_table_shape "S150 A3 mixed-model" "$output_mixedmodel"
[ "$(row_status "$output_mixedmodel" 1)" = "evidenced" ] || fail "S150 A3 mixed-model — expected gate 1 evidenced with all four stages present but differing models, got '$(row_status "$output_mixedmodel" 1)'"
# shellcheck disable=SC2016  # backticks are literal Markdown, not command substitution
expected_evidence_mixedmodel='`model-record` markers on PR #279 for Discovery, Planning, Test, Implementation (Discovery=`claude-opus-5`, Planning=`claude-opus-5`, Test=`claude-opus-5`, Implementation=`claude-sonnet-5`)'
evidence_mixedmodel="$(row_evidence "$output_mixedmodel" 1)"
[ "$evidence_mixedmodel" = "$expected_evidence_mixedmodel" ] || {
  fail "S150 A3 mixed-model — gate 1 evidence cell wrong (stray leading space regression?):"
  printf 'expected: %s\n' "$expected_evidence_mixedmodel" >&2
  printf 'got:      %s\n' "$evidence_mixedmodel" >&2
}
case "$evidence_mixedmodel" in
  *"( Discovery="*) fail "S150 A3 mixed-model — evidence cell has the stray leading space after '(' (regression of the A3 rendering bug): $evidence_mixedmodel" ;;
esac

# =========================================================================
# AC3 — a missing gate renders as missing, run does not abort.
# =========================================================================

# Fixture A: AC1's arm with the stage=Test marker removed.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac3a="$(cat "$FAKEGH_OUT")"
output_ac3a="$(PATH="$fakebin_ac3a:$PATH" "$script" 279)"
status_ac3a=$?
[ "$status_ac3a" -eq 0 ] || fail "S150 AC3a — expected exit 0 with a missing stage, got $status_ac3a"
assert_table_shape "S150 AC3a" "$output_ac3a"
[ "$(row_status "$output_ac3a" 1)" = "not-evidenced" ] || fail "S150 AC3a — expected gate 1 not-evidenced when stage=Test is missing, got '$(row_status "$output_ac3a" 1)'"
[ "$(row_status "$output_ac3a" 2)" = "evidenced" ] || fail "S150 AC3a — gate 2 should be unaffected by a missing stage 1 marker"
[ "$(row_status "$output_ac3a" 3)" = "evidenced" ] || fail "S150 AC3a — gate 3 should be unaffected"
[ "$(row_status "$output_ac3a" 4)" = "evidenced" ] || fail "S150 AC3a — gate 4 should be unaffected"

# Fixture B (finding (f)): AC1's arm with the ISSUE line removed
# entirely — zero closing issues. Gate 5 must go not-evidenced, call C
# must not be made at all (no __CALL_C265__ arm at all; the fallthrough
# would fire and exit 1 if the collector called it anyway), and the run
# must still emit six rows and exit 0.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
echo "S150 AC3b: unexpected gh call: $*" >> "$SANDBOX/gh-witness-ac3b"
exit 1
GHEOF
fakebin_ac3b="$(cat "$FAKEGH_OUT")"
output_ac3b="$(PATH="$fakebin_ac3b:$PATH" "$script" 279)"
status_ac3b=$?
[ "$status_ac3b" -eq 0 ] || fail "S150 AC3b — expected exit 0 with zero closing issues, got $status_ac3b"
assert_table_shape "S150 AC3b" "$output_ac3b"
[ "$(row_status "$output_ac3b" 5)" = "not-evidenced" ] || fail "S150 AC3b — expected gate 5 not-evidenced with no closing issues, got '$(row_status "$output_ac3b" 5)'"
[ ! -s "$SANDBOX/gh-witness-ac3b" ] || fail "S150 AC3b — a gh call was made that shouldn't have been (likely gh issue view with an empty issue list): $(cat "$SANDBOX/gh-witness-ac3b")"

# =========================================================================
# AC4 — human-only gate (merge confirmation) is neither faked nor failed:
# always unverifiable-from-artifacts, never derived from mergedBy/mergedAt
# or from merge state, never collapsing into AC3's not-evidenced.
# =========================================================================

# Fixture A: AC1's fixture (merged, mergedBy present).
[ "$(row_status "$output_ac1" 6)" = "unverifiable-from-artifacts" ] || fail "S150 AC4a — expected gate 6 unverifiable-from-artifacts on a merged PR, got '$(row_status "$output_ac1" 6)'"

# Fixture B: every other gate not-evidenced (no markers, zero checks, no
# closing issue) — gate 6 must still be unverifiable-from-artifacts and
# textually distinct from the other five rows' not-evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-01-01T00:00:00Z\n'
    printf 'MERGEDBY\tsomeone\n'
    exit 0 ;;
  __CALL_B__)
    echo "no checks reported on the given branch" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac4b="$(cat "$FAKEGH_OUT")"
output_ac4b="$(PATH="$fakebin_ac4b:$PATH" "$script" 279)"
status_ac4b=$?
[ "$status_ac4b" -eq 0 ] || fail "S150 AC4b — expected exit 0 with every gate absent, got $status_ac4b"
assert_table_shape "S150 AC4b" "$output_ac4b"
for n in 1 2 3 4 5; do
  [ "$(row_status "$output_ac4b" "$n")" = "not-evidenced" ] || fail "S150 AC4b — expected gate $n not-evidenced, got '$(row_status "$output_ac4b" "$n")'"
done
[ "$(row_status "$output_ac4b" 6)" = "unverifiable-from-artifacts" ] || fail "S150 AC4b — gate 6 must stay unverifiable-from-artifacts even when everything else is not-evidenced (must not collapse into AC3), got '$(row_status "$output_ac4b" 6)'"

# Fixture C: an open (unmerged) PR — gate 6 must not flip either way.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'
    printf 'STATE\tOPEN\n'
    printf 'MERGEDAT\t\n'
    printf 'MERGEDBY\t\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac4c="$(cat "$FAKEGH_OUT")"
output_ac4c="$(PATH="$fakebin_ac4c:$PATH" "$script" 279)"
assert_table_shape "S150 AC4c" "$output_ac4c"
[ "$(row_status "$output_ac4c" 6)" = "unverifiable-from-artifacts" ] || fail "S150 AC4c — gate 6 must be unverifiable-from-artifacts on an open PR too, got '$(row_status "$output_ac4c" 6)'"

# =========================================================================
# AC5 — read-only: no gh write call is ever made, and the source contains
# none. Strengthened per finding (g): the assertion is a conjunction
# (witness empty AND exit 0 AND full six-row table), so a script that
# does nothing at all can't pass it vacuously.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
echo "$*" >> "$SANDBOX/gh-witness-ac5"
exit 1
GHEOF
fakebin_ac5="$(cat "$FAKEGH_OUT")"
output_ac5="$(PATH="$fakebin_ac5:$PATH" "$script" 279)"
status_ac5=$?
witness_ac5=""
[ -f "$SANDBOX/gh-witness-ac5" ] && witness_ac5="$(cat "$SANDBOX/gh-witness-ac5")"
if [ -n "$witness_ac5" ] || [ "$status_ac5" -ne 0 ]; then
  fail "S150 AC5 — expected an empty witness AND exit 0; witness='$witness_ac5' exit=$status_ac5"
fi
assert_table_shape "S150 AC5 (conjunction: full table too)" "$output_ac5"

# AC5(b): source-level grep for a gh write subcommand, with comment
# lines stripped first (finding (h) — otherwise the header's own prose
# documenting "never calls gh pr comment" would false-positive, the
# same trap S113 exists to avoid).
stripped_source="$(sed -E 's/^[[:space:]]*#.*$//' "$script")"
for banned in "pr merge" "pr comment" "issue comment" "issue edit" "pr edit" "api -X" "api --method"; do
  if grep -qF -- "$banned" <<<"$stripped_source"; then
    fail "S150 AC5 — compliance-evidence.sh's source (comments stripped) contains a gh write subcommand: '$banned'"
  fi
done
# "label" checked separately as a whole word ("gh ... label"), since it's
# a common substring (e.g. inside unrelated prose) — this repo's own
# label-writing shape is "gh <noun> ... label" or "gh label".
if grep -qE '\bgh\b[^|&;]*\blabel\b' <<<"$stripped_source"; then
  fail "S150 AC5 — compliance-evidence.sh's source (comments stripped) appears to call a gh ... label subcommand"
fi

# =========================================================================
# AC6 — offline: with no gh on PATH, exits 3, nothing on stdout, a
# message on stderr. (Determinism was checked above, under AC1.)
# =========================================================================
nogh_path="$(path_without_gh)"
output_nogh="$(PATH="$nogh_path" "$script" 279 2>/tmp/s150_stderr_nogh.$$)"
status_nogh=$?
stderr_nogh="$(cat /tmp/s150_stderr_nogh.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_nogh.$$
[ "$status_nogh" -eq 3 ] || fail "S150 AC6 — expected exit 3 with no gh on PATH, got $status_nogh"
[ -z "$output_nogh" ] || fail "S150 AC6 — expected empty stdout with no gh on PATH, got: $output_nogh"
[ -n "$stderr_nogh" ] || fail "S150 AC6 — expected a message on stderr with no gh on PATH"

# =========================================================================
# AC7 — discoverable, correctly wired: not check-prefixed, not invoked
# by ./check (finding (b) — Architect's contract had no arm for this at
# all).
# =========================================================================
[ -x "$script" ] || fail "S150 AC7 — compliance-evidence.sh must exist at repo root and be executable"
case "$(basename "$script")" in
  check-*) fail "S150 AC7 — compliance-evidence.sh must not be named with a check- prefix (it's not a ./check gate, AC7)" ;;
esac
if grep -q 'compliance-evidence' "$TEST_REPO_ROOT/check"; then
  fail "S150 AC7 — ./check must not reference compliance-evidence.sh (it needs gh/network; ./check must stay usable offline)"
fi

# =========================================================================
# AC8 — the four-state status vocabulary, per gate.
# =========================================================================

# AC8a — an unparseable review marker (malformed sha) renders
# indeterminate, distinct from AC8c's not-evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=abc123 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8a="$(cat "$FAKEGH_OUT")"
output_ac8a="$(PATH="$fakebin_ac8a:$PATH" "$script" 279)"
assert_table_shape "S150 AC8a" "$output_ac8a"
[ "$(row_status "$output_ac8a" 3)" = "indeterminate" ] || fail "S150 AC8a — expected gate 3 indeterminate for a malformed sha, got '$(row_status "$output_ac8a" 3)'"
evidence_ac8a="$(row_evidence "$output_ac8a" 3)"
[ -n "$(printf '%s' "$evidence_ac8a" | sed -E 's/^ +| +$//g')" ] || fail "S150 AC8a — Evidence cell for the indeterminate row must not be empty (AC2)"

# AC8b — an unknown CI bucket renders indeterminate, never evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tWEIRD\tsomething-new\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8b="$(cat "$FAKEGH_OUT")"
output_ac8b="$(PATH="$fakebin_ac8b:$PATH" "$script" 279)"
assert_table_shape "S150 AC8b" "$output_ac8b"
[ "$(row_status "$output_ac8b" 4)" = "indeterminate" ] || fail "S150 AC8b — expected gate 4 indeterminate for an unrecognized bucket, got '$(row_status "$output_ac8b" 4)'"

# AC8c — a stale review marker (sha != headRefOid) is not-evidenced, NOT
# indeterminate: it's a recognized, interpretable artifact that just
# evidences a review of a different commit.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=472bc8f574c4aea3fc58161d1924b7b05329172f -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8c="$(cat "$FAKEGH_OUT")"
output_ac8c="$(PATH="$fakebin_ac8c:$PATH" "$script" 279)"
assert_table_shape "S150 AC8c" "$output_ac8c"
[ "$(row_status "$output_ac8c" 3)" = "not-evidenced" ] || fail "S150 AC8c — expected gate 3 not-evidenced for a stale (sha-mismatched) marker, got '$(row_status "$output_ac8c" 3)'"

# --- Arm E (AC3a, issue #299): the non-degraded branch of P3 loses its
# stray ` -->` too, and otherwise stays byte-for-byte as today (including
# "it doesn't match"). This is the exact gap D1 warned about: a fix that
# drops ` -->` in the degraded branch only, while leaving this one
# untouched, must fail here.
# shellcheck disable=SC2016
expected_ac8c_evidence='only a stale `pre-merge-review:done sha=472bc8f574c4aea3fc58161d1924b7b05329172f` marker on PR #279; it doesn'"'"'t match `headRefOid` (6e00a8c38bf18f19cd53084b5c77ae476c1e74e6)'
[ "$(row_evidence "$output_ac8c" 3)" = "$expected_ac8c_evidence" ] || fail "S150 AC3a — gate 3 (non-degraded) evidence text doesn't match: '$(row_evidence "$output_ac8c" 3)'"
case "$(row_evidence "$output_ac8c" 3)" in
  *"-->"*) fail "S150 AC3a — the stray '-->' is still present in the non-degraded gate-3 evidence cell" ;;
esac

# AC8d (finding (c), highest-value gap) — a red CI check is not-evidenced,
# never evidenced. The single most likely wrong implementation
# ("checks parsed -> evidenced") reports a red build as compliant; this
# is the arm that catches it.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tFAILURE\tfail\n'
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac8d="$(cat "$FAKEGH_OUT")"
output_ac8d="$(PATH="$fakebin_ac8d:$PATH" "$script" 279)"
status_ac8d=$?
[ "$status_ac8d" -eq 0 ] || fail "S150 AC8d — expected exit 0 with a red CI check, got $status_ac8d"
assert_table_shape "S150 AC8d" "$output_ac8d"
[ "$(row_status "$output_ac8d" 4)" = "not-evidenced" ] || fail "S150 AC8d — expected gate 4 not-evidenced for a red (bucket=fail) check, got '$(row_status "$output_ac8d" 4)'"
case "$(row_evidence "$output_ac8d" 4)" in
  *check*) : ;;
  *) fail "S150 AC8d — the failing check should be named in the Evidence cell (AC2): $(row_evidence "$output_ac8d" 4)" ;;
esac

# AC8e (finding (d)) — a pending CI check is indeterminate: the check
# exists, its outcome is not yet knowable.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tPENDING\tpending\n'
    exit 8 ;;
esac
exit 1
GHEOF
fakebin_ac8e="$(cat "$FAKEGH_OUT")"
output_ac8e="$(PATH="$fakebin_ac8e:$PATH" "$script" 279)"
assert_table_shape "S150 AC8e" "$output_ac8e"
[ "$(row_status "$output_ac8e" 4)" = "indeterminate" ] || fail "S150 AC8e — expected gate 4 indeterminate for bucket=pending, got '$(row_status "$output_ac8e" 4)'"

# AC8f (finding (d)) — zero CI checks at all is not-evidenced: nothing
# to have passed. gh pr checks itself exits non-zero here (D6's trap);
# an implementation reading the exit code first would wrongly report
# indeterminate.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    exit 0 ;;
  __CALL_B__)
    echo "no checks reported on the given branch" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac8f="$(cat "$FAKEGH_OUT")"
output_ac8f="$(PATH="$fakebin_ac8f:$PATH" "$script" 279)"
status_ac8f=$?
[ "$status_ac8f" -eq 0 ] || fail "S150 AC8f — expected exit 0 with zero CI checks, got $status_ac8f"
assert_table_shape "S150 AC8f" "$output_ac8f"
[ "$(row_status "$output_ac8f" 4)" = "not-evidenced" ] || fail "S150 AC8f — expected gate 4 not-evidenced with zero checks, got '$(row_status "$output_ac8f" 4)'"

# AC8g — a stage=Test marker matching tolerantly but written unquoted
# (model=Sonnet, no quotes) is indeterminate: model-record-gate.sh
# deliberately goes silent on this form, but this collector must not
# fold "present but oddly written" into either evidenced or
# not-evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model=Sonnet effort=medium -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8g="$(cat "$FAKEGH_OUT")"
output_ac8g="$(PATH="$fakebin_ac8g:$PATH" "$script" 279)"
assert_table_shape "S150 AC8g" "$output_ac8g"
[ "$(row_status "$output_ac8g" 1)" = "indeterminate" ] || fail "S150 AC8g — expected gate 1 indeterminate for an unquoted (malformed) stage marker, got '$(row_status "$output_ac8g" 1)'"

# --- Gate 2 negatives (finding (e)): Architect's only gate-2 exercise
# was AC1's positive (a non-empty same-model-exception). "A stage=Review
# marker exists -> evidenced" would pass the whole contracted suite
# without these.

# Same model, no exception at all.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2_same="$(cat "$FAKEGH_OUT")"
output_g2_same="$(PATH="$fakebin_g2_same:$PATH" "$script" 279)"
assert_table_shape "S150 gate2-negative (same model, no exception)" "$output_g2_same"
[ "$(row_status "$output_g2_same" 2)" = "not-evidenced" ] || fail "S150 gate2-negative — same model with no exception must be not-evidenced, got '$(row_status "$output_g2_same" 2)'"

# Same model, empty-reason exception (same-model-exception="") — an
# empty reason must not satisfy (PR #253's trap).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2_empty="$(cat "$FAKEGH_OUT")"
output_g2_empty="$(PATH="$fakebin_g2_empty:$PATH" "$script" 279)"
assert_table_shape "S150 gate2-negative (empty-reason exception)" "$output_g2_empty"
[ "$(row_status "$output_g2_empty" 2)" = "not-evidenced" ] || fail "S150 gate2-negative — an empty-reason same-model-exception must still be not-evidenced, got '$(row_status "$output_g2_empty" 2)'"

# Genuinely the same model under different label styles ("claude-sonnet-5"
# vs "Sonnet 5") must still be flagged (#268's normalize_model, D5's
# verbatim-copy decision — if reimplemented differently the collector
# silently disagrees with the gate it reports on).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="Sonnet 5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2_label="$(cat "$FAKEGH_OUT")"
output_g2_label="$(PATH="$fakebin_g2_label:$PATH" "$script" 279)"
assert_table_shape "S150 gate2-negative (label normalization)" "$output_g2_label"
[ "$(row_status "$output_g2_label" 2)" = "not-evidenced" ] || fail "S150 gate2-negative — 'claude-sonnet-5' vs 'Sonnet 5' must normalize equal and be not-evidenced, got '$(row_status "$output_g2_label" 2)'"

# =========================================================================
# Finding (f): the empty-collection [] ? paths. Two closing issues — call
# C must be made for both; an implementation reading only the first would
# wrongly report Discovery missing.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tdddddddddddddddddddddddddddddddddddddddd\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_twoissues="$(cat "$FAKEGH_OUT")"
output_twoissues="$(PATH="$fakebin_twoissues:$PATH" "$script" 279)"
assert_table_shape "S150 two-issues" "$output_twoissues"
[ "$(row_status "$output_twoissues" 1)" = "evidenced" ] || fail "S150 two-issues — expected gate 1 evidenced only if BOTH closing issues are read (Discovery lives on the second), got '$(row_status "$output_twoissues" 1)'"

# =========================================================================
# The two failure paths (Architect's contract, unchanged) + a third:
# call A itself failing.
# =========================================================================

# Call B genuinely fails: Call A valid, Call B exits 1 with nothing
# parseable on stdout and an unrelated message on stderr (NOT the
# zero-checks message) -> gate 4 indeterminate, exit 0, other five rows
# intact, and no stderr text interleaved into stdout.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    echo "gh: a transient network problem occurred" >&2
    exit 1 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_callb_fails="$(cat "$FAKEGH_OUT")"
output_callb_fails="$(PATH="$fakebin_callb_fails:$PATH" "$script" 279)"
status_callb_fails=$?
[ "$status_callb_fails" -eq 0 ] || fail "S150 call-B-fails — expected exit 0, got $status_callb_fails"
assert_table_shape "S150 call-B-fails" "$output_callb_fails"
[ "$(row_status "$output_callb_fails" 4)" = "indeterminate" ] || fail "S150 call-B-fails — expected gate 4 indeterminate on a genuine call-B failure, got '$(row_status "$output_callb_fails" 4)'"
[ "$(row_status "$output_callb_fails" 1)" = "evidenced" ] || fail "S150 call-B-fails — the other gates must be unaffected by a call-B failure"
case "$output_callb_fails" in
  *"transient network"*) fail "S150 call-B-fails — stderr text leaked into the stdout table" ;;
  *) : ;;
esac

# Call C fails for a closing issue: Discovery lives only on the issue,
# and its lookup fails transiently -> gate 1 indeterminate (not
# not-evidenced — the exact regression model-record-gate.sh had, PR #249
# round 2), exit 0, warning on stderr.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
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
fakebin_callc_fails="$(cat "$FAKEGH_OUT")"
output_callc_fails="$(PATH="$fakebin_callc_fails:$PATH" "$script" 279 2>/tmp/s150_stderr_callc.$$)"
status_callc_fails=$?
stderr_callc_fails="$(cat /tmp/s150_stderr_callc.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_callc.$$
[ "$status_callc_fails" -eq 0 ] || fail "S150 call-C-fails — expected exit 0, got $status_callc_fails"
assert_table_shape "S150 call-C-fails" "$output_callc_fails"
[ "$(row_status "$output_callc_fails" 1)" = "indeterminate" ] || fail "S150 call-C-fails — expected gate 1 indeterminate (not not-evidenced) when a closing issue lookup fails and Discovery then looks missing, got '$(row_status "$output_callc_fails" 1)'"
assert_contains "S150 call-C-fails — a warning appears on stderr" "warning" "$stderr_callc_fails"

# --- AC1/AC2 (issue #299): this fixture already puts gate 2 in P1 (no
# stage=Review marker at all) and gate 3 in P2 (no pre-merge-review:done
# text of any shape) while the issue lookup has failed — both defective
# paths already execute here today, unasserted. Assert they degrade to
# indeterminate rather than asserting absence, with the exact evidence
# text AC1/AC2 specify (not a substring: a fix that names the wrong PR,
# drops a marker name, or merges the two gates' messages must fail here).
[ "$(row_status "$output_callc_fails" 2)" = "indeterminate" ] || fail "S150 AC1 — expected gate 2 indeterminate (not not-evidenced) when a closing issue lookup fails and stage=Review looks missing, got '$(row_status "$output_callc_fails" 2)'"
[ "$(row_status "$output_callc_fails" 3)" = "indeterminate" ] || fail "S150 AC2 — expected gate 3 indeterminate (not not-evidenced) when a closing issue lookup fails and no pre-merge-review:done marker is found, got '$(row_status "$output_callc_fails" 3)'"
# shellcheck disable=SC2016
expected_ac1_evidence='no `stage=Review` and/or `stage=Implementation` model-record marker found on PR #279, but a closing issue lookup failed, so absence can'"'"'t be confirmed'
[ "$(row_evidence "$output_callc_fails" 2)" = "$expected_ac1_evidence" ] || fail "S150 AC1 — gate 2 evidence text doesn't match the spec'd template: $(row_evidence "$output_callc_fails" 2)"
# shellcheck disable=SC2016
expected_ac2_evidence='no `pre-merge-review:done` marker found on PR #279, but a closing issue lookup failed, so absence can'"'"'t be confirmed'
[ "$(row_evidence "$output_callc_fails" 3)" = "$expected_ac2_evidence" ] || fail "S150 AC2 — gate 3 evidence text doesn't match the spec'd template: $(row_evidence "$output_callc_fails" 3)"

# --- AC7 (issue #299), a.k.a. Arm F: the stderr warning must name every
# affected gate, not just gate 1, and must still be the place the failing
# issue number is disclosed (AC4: the table itself never names it).
assert_contains "S150 AC7 — the warning names every affected gate" "gates that search its comments" "$stderr_callc_fails"
case "$stderr_callc_fails" in
  *"stage evidence involving it"*)
    fail "S150 AC7 — the warning still carries the old gate-1-only wording" ;;
esac
assert_contains "S150 AC7 — the warning names the issue" "#265" "$stderr_callc_fails"
# AC4: the table's own cells must not name the failing issue (the
# careful negative: #279 legitimately appears in every cell, so this
# checks for the issue number specifically, not any '#').
for n in 1 2 3; do
  case "$(row_evidence "$output_callc_fails" "$n")" in
    *"#265"*) fail "S150 AC4 — row $n names the failing issue #265 in the table; that belongs on stderr only" ;;
  esac
done

# =========================================================================
# Arm B (AC3/AC3a, issue #299): gate 3's P3 (stale sha, no match) must
# degrade to indeterminate when the issue lookup fails, and the evidence
# text must keep reporting BOTH shas — a fix that degrades the status by
# discarding the sha detail must fail here.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb -->\n'
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
fakebin_ac3="$(cat "$FAKEGH_OUT")"
output_ac3="$(PATH="$fakebin_ac3:$PATH" "$script" 279 2>"$SANDBOX/s150_stderr_ac3")"
status_ac3=$?
[ "$status_ac3" -eq 0 ] || fail "S150 AC3 — expected exit 0, got $status_ac3"
assert_table_shape "S150 AC3" "$output_ac3"
[ "$(row_status "$output_ac3" 3)" = "indeterminate" ] || fail "S150 AC3 — expected gate 3 indeterminate for a stale marker under a failed issue lookup, got '$(row_status "$output_ac3" 3)'"
# shellcheck disable=SC2016
expected_ac3_evidence='only a stale `pre-merge-review:done sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` marker on PR #279, which doesn'"'"'t match `headRefOid` (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa), and a closing issue lookup failed, so a matching marker can'"'"'t be ruled out'
[ "$(row_evidence "$output_ac3" 3)" = "$expected_ac3_evidence" ] || fail "S150 AC3 — gate 3 evidence text doesn't match the spec'd template: $(row_evidence "$output_ac3" 3)"
case "$(row_evidence "$output_ac3" 3)" in
  *"-->"*) fail "S150 AC3a — the stray '-->' is still present in the degraded gate-3 evidence cell" ;;
esac

# =========================================================================
# Arm C (AC5, issue #299): two closing issues, one fetch succeeding and
# one failing. Gate 1 must reflect the marker that came from the
# successful fetch (evidenced), while gates 2 and 3 — which found no
# marker at all in the corpus they COULD read — must be indeterminate,
# not not-evidenced. Only this pairing distinguishes "one of two failed"
# from "both failed" (Arm A already covers "both/none succeeded"). If this
# arm needs a line of production code beyond AC1-AC3's guards, the fix is
# wrong.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tdddddddddddddddddddddddddddddddddddddddd\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_C266__)
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac5="$(cat "$FAKEGH_OUT")"
output_ac5="$(PATH="$fakebin_ac5:$PATH" "$script" 279 2>"$SANDBOX/s150_stderr_ac5_partial")"
status_ac5=$?
[ "$status_ac5" -eq 0 ] || fail "S150 AC5 — expected exit 0, got $status_ac5"
assert_table_shape "S150 AC5" "$output_ac5"
[ "$(row_status "$output_ac5" 1)" = "evidenced" ] || fail "S150 AC5 — expected gate 1 evidenced (Discovery came from the successful fetch), got '$(row_status "$output_ac5" 1)'"
[ "$(row_status "$output_ac5" 2)" = "indeterminate" ] || fail "S150 AC5 — expected gate 2 indeterminate when one of two closing-issue fetches failed, got '$(row_status "$output_ac5" 2)'"
[ "$(row_status "$output_ac5" 3)" = "indeterminate" ] || fail "S150 AC5 — expected gate 3 indeterminate when one of two closing-issue fetches failed, got '$(row_status "$output_ac5" 3)'"

# =========================================================================
# Arm D (AC6 guard, issue #299 — Architect's Arm D / Product's D3 ruling).
# This is the arm that can actually fail against an over-broad fix (one
# that flips every not-evidenced to indeterminate whenever the flag is
# set, or a blanket rule at the row()/render seam): it constructs the one
# corpus where a SOUND not-evidenced (gate 2's same-model verdict, gate
# 4's zero-checks verdict) coexists with a failed issue lookup. Neither
# may change status. Row 3's indeterminate assertion is a positive
# control: if a "fix" swallows call C's failure instead of degrading
# gates 2/3, rows 2/4 would stay not-evidenced for the wrong reason and
# this arm would pass vacuously without it.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\teeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    echo "no checks reported on the given branch" >&2
    exit 1 ;;
  __CALL_C265__)
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac6_guard="$(cat "$FAKEGH_OUT")"
output_ac6_guard="$(PATH="$fakebin_ac6_guard:$PATH" "$script" 279 2>"$SANDBOX/s150_stderr_ac6guard")"
status_ac6_guard=$?
[ "$status_ac6_guard" -eq 0 ] || fail "S150 AC6-guard — expected exit 0, got $status_ac6_guard"
assert_table_shape "S150 AC6-guard" "$output_ac6_guard"
[ "$(row_status "$output_ac6_guard" 2)" = "not-evidenced" ] || fail "S150 AC6-guard — THE GUARD: gate 2's same-model verdict must stay not-evidenced under a failed issue lookup (both markers were actually read), got '$(row_status "$output_ac6_guard" 2)'"
[ "$(row_status "$output_ac6_guard" 4)" = "not-evidenced" ] || fail "S150 AC6-guard — THE GUARD: gate 4's zero-checks verdict must stay not-evidenced under a failed issue lookup, got '$(row_status "$output_ac6_guard" 4)'"
[ "$(row_status "$output_ac6_guard" 3)" = "indeterminate" ] || fail "S150 AC6-guard — positive control: gate 3 (no marker at all) must still degrade to indeterminate in this same arm, got '$(row_status "$output_ac6_guard" 3)'"
# shellcheck disable=SC2016
expected_ac6_g2_evidence='`stage=Review` and `stage=Implementation` markers on PR #279 both record `claude-sonnet-5` with no `same-model-exception`'
[ "$(row_evidence "$output_ac6_guard" 2)" = "$expected_ac6_g2_evidence" ] || fail "S150 AC6-guard — gate 2's evidence text must not change either (a degradation clause appended to the message would still be a fix that touched a sound path): '$(row_evidence "$output_ac6_guard" 2)'"

# =========================================================================
# Arm G (issue #302 / P2-1, half 1): naive `tail -1` over the flat
# accumulated corpus makes gate 2's verdict depend on `BUNDLE_ISSUES`
# order, not on any real recency signal — with BOTH closing-issue
# fetches succeeding, so this is not the "corpus incomplete" failure
# mode Arm D/AC6 guards against. Two closing issues, no lookup failure:
# PR body records Implementation=`claude-sonnet-5`; issue #265 records
# Review=`claude-sonnet-5` (same model, would be not-evidenced alone);
# issue #266 records Review=`claude-opus-5` (differs, would be evidenced
# alone). Both markers were actually read — this is genuinely
# conflicting evidence, not a gap — so the correct answer is
# `indeterminate`, and it must come back the same way regardless of
# which issue GitHub happens to list first in `closingIssuesReferences`.
# A naive `tail -1` implementation instead flips between `evidenced` and
# `not-evidenced` purely based on issue order — this is the arm that
# must fail red against that implementation. A "fix" that just makes gate
# 2 always evidenced/not-evidenced regardless of order (rather than
# actually detecting the conflict) is caught by the two sub-cases run
# below with the issue order swapped: both must render the SAME status,
# and it must be `indeterminate`, not silently picking a side.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tffffffffffffffffffffffffffffffffffffffff\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_order1="$(cat "$FAKEGH_OUT")"
output_ac302_order1="$(PATH="$fakebin_ac302_order1:$PATH" "$script" 279)"
status_ac302_order1=$?
[ "$status_ac302_order1" -eq 0 ] || fail "S150 issue #302 Arm G (order 1) — expected exit 0, got $status_ac302_order1"
assert_table_shape "S150 issue #302 Arm G (order 1)" "$output_ac302_order1"
[ "$(row_status "$output_ac302_order1" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm G (order 1) — expected gate 2 indeterminate for genuinely conflicting Review markers across two closing issues, got '$(row_status "$output_ac302_order1" 2)'"

# Same data, swapped issue order (#266 read before #265, mirroring the
# fact closingIssuesReferences order isn't a promise). The verdict must
# not flip.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tffffffffffffffffffffffffffffffffffffffff\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t266\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_order2="$(cat "$FAKEGH_OUT")"
output_ac302_order2="$(PATH="$fakebin_ac302_order2:$PATH" "$script" 279)"
status_ac302_order2=$?
[ "$status_ac302_order2" -eq 0 ] || fail "S150 issue #302 Arm G (order 2) — expected exit 0, got $status_ac302_order2"
assert_table_shape "S150 issue #302 Arm G (order 2)" "$output_ac302_order2"
[ "$(row_status "$output_ac302_order2" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm G (order 2) — expected gate 2 indeterminate for genuinely conflicting Review markers across two closing issues (swapped order), got '$(row_status "$output_ac302_order2" 2)'"
[ "$(row_status "$output_ac302_order1" 2)" = "$(row_status "$output_ac302_order2" 2)" ] || fail "S150 issue #302 Arm G — gate 2's status must not depend on closing-issue order: order1='$(row_status "$output_ac302_order1" 2)' order2='$(row_status "$output_ac302_order2" 2)'"

# =========================================================================
# Arm H (issue #302 / P2-1, half 2 — the exact meta-review repro): TWO
# closing issues, one succeeds (supplying BOTH the Implementation and
# Review markers, same model, no exception), the other's lookup fails.
# Gate 2's old terminal `not-evidenced` branch was unguarded by
# BUNDLE_ISSUE_LOOKUP_FAILED, on the theory that "both markers were read
# so the verdict rests on data in hand" — true for a single closing
# issue, false here: the unread second issue could have carried a
# superseding `stage=Review` marker (as META-REVIEW-PILOT-2.md's P2-1
# demonstrated by flipping call C266 from failing to succeeding with a
# different model, which flipped the verdict from not-evidenced to
# evidenced). With >=2 closing issues and a failed lookup, gate 2 must
# now degrade to indeterminate too, same as gates 1 and 3 already do.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tffffffffffffffffffffffffffffffffffffffff\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_C266__)
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac302_partial="$(cat "$FAKEGH_OUT")"
output_ac302_partial="$(PATH="$fakebin_ac302_partial:$PATH" "$script" 279)"
status_ac302_partial=$?
[ "$status_ac302_partial" -eq 0 ] || fail "S150 issue #302 Arm H — expected exit 0, got $status_ac302_partial"
assert_table_shape "S150 issue #302 Arm H" "$output_ac302_partial"
[ "$(row_status "$output_ac302_partial" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm H — expected gate 2 indeterminate: both markers read came from one of two closing issues, and the other's fetch failed (a superseding marker there can't be ruled out), got '$(row_status "$output_ac302_partial" 2)'"

# =========================================================================
# Arm I (issue #302 review round 1, R-1 — the PR #301 live-data
# regression). PR-side and issue-side markers for the SAME stage
# disagree: the PR's own `stage=Review` marker records what actually
# ran (`claude-opus-5`); the single closing issue #265 carries a
# `stage=Review` marker recording an earlier PLAN (`claude-sonnet-5`,
# e.g. from Planning). This is precisely the #299/#301 shape Reviewer
# found live. Per issue #253's precedent (inherited, not re-earned):
# the PR-side marker wins — this is not a conflict, and gate 2 must
# render a definite verdict (`evidenced`, since opus != the
# `stage=Implementation` sonnet), never `indeterminate`.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\teeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_pr_wins="$(cat "$FAKEGH_OUT")"
output_ac302_pr_wins="$(PATH="$fakebin_ac302_pr_wins:$PATH" "$script" 279)"
status_ac302_pr_wins=$?
[ "$status_ac302_pr_wins" -eq 0 ] || fail "S150 issue #302 Arm I — expected exit 0, got $status_ac302_pr_wins"
assert_table_shape "S150 issue #302 Arm I" "$output_ac302_pr_wins"
[ "$(row_status "$output_ac302_pr_wins" 2)" = "evidenced" ] || fail "S150 issue #302 Arm I — expected gate 2 evidenced: the PR's own stage=Review marker (claude-opus-5) must win over the issue's planned one (claude-sonnet-5), got '$(row_status "$output_ac302_pr_wins" 2)'"

# =========================================================================
# Arm J (issue #302 review round 1, R-2 — the missing positive multi-
# issue arm). Reviewer showed a four-line straw man ("gate 2 is always
# `indeterminate` whenever the PR names >= 2 closing issues") passes
# every existing arm, Arms G/H included. This arm closes that gap: TWO
# closing issues, BOTH fetches succeed, and the sources actually agree
# — issue #266 has no markers at all, so the only Review marker is
# issue #265's, uncontested. The correct verdict is a DEFINITE
# `evidenced` (opus != the PR's Implementation sonnet), which the
# straw man cannot produce (it always renders `indeterminate` here).
# Run both issue orders: gate 2 must be `evidenced` either way.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tabababababababababababababababababababab\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_positive1="$(cat "$FAKEGH_OUT")"
output_ac302_positive1="$(PATH="$fakebin_ac302_positive1:$PATH" "$script" 279)"
status_ac302_positive1=$?
[ "$status_ac302_positive1" -eq 0 ] || fail "S150 issue #302 Arm J (order 1) — expected exit 0, got $status_ac302_positive1"
assert_table_shape "S150 issue #302 Arm J (order 1)" "$output_ac302_positive1"
[ "$(row_status "$output_ac302_positive1" 2)" = "evidenced" ] || fail "S150 issue #302 Arm J (order 1) — expected a DEFINITE gate 2 evidenced with two closing issues read and sources agreeing (uncontested), got '$(row_status "$output_ac302_positive1" 2)' — a naive 'always indeterminate at >=2 issues' implementation would fail this"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tabababababababababababababababababababab\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t266\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_positive2="$(cat "$FAKEGH_OUT")"
output_ac302_positive2="$(PATH="$fakebin_ac302_positive2:$PATH" "$script" 279)"
status_ac302_positive2=$?
[ "$status_ac302_positive2" -eq 0 ] || fail "S150 issue #302 Arm J (order 2) — expected exit 0, got $status_ac302_positive2"
assert_table_shape "S150 issue #302 Arm J (order 2)" "$output_ac302_positive2"
[ "$(row_status "$output_ac302_positive2" 2)" = "evidenced" ] || fail "S150 issue #302 Arm J (order 2) — expected the same DEFINITE gate 2 evidenced with issue order swapped, got '$(row_status "$output_ac302_positive2" 2)'"

# =========================================================================
# Arm K (issue #302 review round 1, R-3 — same model, differing
# same-model-exception). Both closing issues carry a `stage=Review`
# marker with the SAME model (`claude-opus-5`, matching the PR's own
# `stage=Implementation`), but issue #265 carries a
# `same-model-exception=` attribute and issue #266 doesn't. That is
# itself a genuine inter-issue disagreement (R-3), and it must render
# `indeterminate` the same way regardless of issue order.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" same-model-exception="only model available" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_exc1="$(cat "$FAKEGH_OUT")"
output_ac302_exc1="$(PATH="$fakebin_ac302_exc1:$PATH" "$script" 279)"
status_ac302_exc1=$?
[ "$status_ac302_exc1" -eq 0 ] || fail "S150 issue #302 Arm K (order 1) — expected exit 0, got $status_ac302_exc1"
assert_table_shape "S150 issue #302 Arm K (order 1)" "$output_ac302_exc1"
[ "$(row_status "$output_ac302_exc1" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm K (order 1) — expected gate 2 indeterminate: same model but disagreeing same-model-exception across two closing issues, got '$(row_status "$output_ac302_exc1" 2)'"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t266\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" same-model-exception="only model available" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_exc2="$(cat "$FAKEGH_OUT")"
output_ac302_exc2="$(PATH="$fakebin_ac302_exc2:$PATH" "$script" 279)"
status_ac302_exc2=$?
[ "$status_ac302_exc2" -eq 0 ] || fail "S150 issue #302 Arm K (order 2) — expected exit 0, got $status_ac302_exc2"
assert_table_shape "S150 issue #302 Arm K (order 2)" "$output_ac302_exc2"
[ "$(row_status "$output_ac302_exc2" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm K (order 2) — expected the same gate 2 indeterminate with issue order swapped, got '$(row_status "$output_ac302_exc2" 2)'"
[ "$(row_status "$output_ac302_exc1" 2)" = "$(row_status "$output_ac302_exc2" 2)" ] || fail "S150 issue #302 Arm K — gate 2 must not depend on closing-issue order: order1='$(row_status "$output_ac302_exc1" 2)' order2='$(row_status "$output_ac302_exc2" 2)'"

# =========================================================================
# Arm L (issue #302 review round 1, R-4 — malformed marker in one
# issue vs. well-formed in another). Issue #265's `stage=Review`
# marker has no quoted `model="..."` at all (malformed but still
# recognized); issue #266's is well-formed. A position-based pick
# (`lines[0]`) previously let whichever issue was fetched first decide
# between `indeterminate` ("no quoted model=") and a definite verdict.
# Must now render `indeterminate` regardless of order.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tefefefefefefefefefefefefefefefefefefefef\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review effort="high" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_malf1="$(cat "$FAKEGH_OUT")"
output_ac302_malf1="$(PATH="$fakebin_ac302_malf1:$PATH" "$script" 279)"
status_ac302_malf1=$?
[ "$status_ac302_malf1" -eq 0 ] || fail "S150 issue #302 Arm L (order 1) — expected exit 0, got $status_ac302_malf1"
assert_table_shape "S150 issue #302 Arm L (order 1)" "$output_ac302_malf1"
[ "$(row_status "$output_ac302_malf1" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm L (order 1) — expected gate 2 indeterminate: a malformed stage=Review marker on one closing issue vs. a well-formed one on another, got '$(row_status "$output_ac302_malf1" 2)'"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tefefefefefefefefefefefefefefefefefefefef\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t266\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-opus-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf 'TEXT\t<!-- model-record: stage=Review effort="high" -->\n'
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac302_malf2="$(cat "$FAKEGH_OUT")"
output_ac302_malf2="$(PATH="$fakebin_ac302_malf2:$PATH" "$script" 279)"
status_ac302_malf2=$?
[ "$status_ac302_malf2" -eq 0 ] || fail "S150 issue #302 Arm L (order 2) — expected exit 0, got $status_ac302_malf2"
assert_table_shape "S150 issue #302 Arm L (order 2)" "$output_ac302_malf2"
[ "$(row_status "$output_ac302_malf2" 2)" = "indeterminate" ] || fail "S150 issue #302 Arm L (order 2) — expected the same gate 2 indeterminate with issue order swapped, got '$(row_status "$output_ac302_malf2" 2)'"
[ "$(row_status "$output_ac302_malf1" 2)" = "$(row_status "$output_ac302_malf2" 2)" ] || fail "S150 issue #302 Arm L — gate 2 must not depend on closing-issue order: order1='$(row_status "$output_ac302_malf1" 2)' order2='$(row_status "$output_ac302_malf2" 2)'"

# =========================================================================
# Presence arm (Product's original AC9 arm, retained as a cheap extra —
# NOT the AC6 guard, per D3: an over-broad fix leaves evidenced paths
# untouched, so this arm cannot catch it. It catches a different mistake
# instead: a guard placed above the branch it belongs in, e.g. at the top
# of gate_review_marker()/gate_review_model() rather than before the
# specific defective branch, which would flip a matching-sha or
# differs-model evidenced row to indeterminate. Also folds in the
# cheap gate-4 bucket=fail non-regression under flag=1 (Architect §3.5).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-opus-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=cccccccccccccccccccccccccccccccccccccccc -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tFAILURE\tfail\n'
    exit 1 ;;
  __CALL_C265__)
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_presence="$(cat "$FAKEGH_OUT")"
output_presence="$(PATH="$fakebin_presence:$PATH" "$script" 279 2>"$SANDBOX/s150_stderr_presence")"
status_presence=$?
[ "$status_presence" -eq 0 ] || fail "S150 presence-arm — expected exit 0, got $status_presence"
assert_table_shape "S150 presence-arm" "$output_presence"
[ "$(row_status "$output_presence" 2)" = "evidenced" ] || fail "S150 presence-arm — gate 2 (models differ) must stay evidenced under a failed issue lookup, got '$(row_status "$output_presence" 2)'"
[ "$(row_status "$output_presence" 3)" = "evidenced" ] || fail "S150 presence-arm — gate 3 (matching sha) must stay evidenced under a failed issue lookup, got '$(row_status "$output_presence" 3)'"
[ "$(row_status "$output_presence" 4)" = "not-evidenced" ] || fail "S150 presence-arm — gate 4's bucket=fail verdict must stay not-evidenced under a failed issue lookup, got '$(row_status "$output_presence" 4)'"

# Call A fails entirely: no honest table is possible -> exit 4, nothing
# on stdout, a message on stderr.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    echo "gh: could not resolve to a PullRequest" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_calla_fails="$(cat "$FAKEGH_OUT")"
output_calla_fails="$(PATH="$fakebin_calla_fails:$PATH" "$script" 279 2>/tmp/s150_stderr_calla.$$)"
status_calla_fails=$?
stderr_calla_fails="$(cat /tmp/s150_stderr_calla.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_calla.$$
[ "$status_calla_fails" -eq 4 ] || fail "S150 call-A-fails — expected exit 4 when the PR itself can't be read, got $status_calla_fails"
[ -z "$output_calla_fails" ] || fail "S150 call-A-fails — expected no table on stdout when call A fails, got: $output_calla_fails"
[ -n "$stderr_calla_fails" ] || fail "S150 call-A-fails — expected a message on stderr"

# =========================================================================
# PR #298 review F2 — a cell that genuinely exceeds the 300-char budget
# (Architect's §3.6 prose: an ellipsis must mark the cut, matching the
# already-observed real-world shape — PR #279's gate-2 cell quoting a
# 118-char exception reason is already ~190 chars, and a longer exception
# or a multi-check gate-4 cell pushes past 300 on real input). Built with
# an over-long same-model-exception on gate 2.
# =========================================================================
long_reason="the fork session inherits its parent model and no other model was made available for this particular review round so this same-model exception documents that limitation in exhaustive detail for the record, repeated once more to push well past the three hundred character budget for this evidence cell"
run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
case "\$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="$long_reason" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_longcell="$(cat "$FAKEGH_OUT")"
output_longcell="$(PATH="$fakebin_longcell:$PATH" "$script" 279)"
assert_table_shape "S150 F2 long-cell" "$output_longcell"
evidence_longcell="$(row_evidence "$output_longcell" 2)"
[ "${#evidence_longcell}" -le 301 ] || fail "S150 F2 long-cell — evidence cell exceeds the 300-char budget plus ellipsis: ${#evidence_longcell} chars"
case "$evidence_longcell" in
  *…) : ;;
  *) fail "S150 F2 long-cell — a cell actually over 300 chars must render with a visible truncation marker (…), got: $evidence_longcell" ;;
esac

# =========================================================================
# PR #298 review F5 — bad usage (no PR number) exits 2, with nothing on
# stdout and a message on stderr.
# =========================================================================
output_badusage="$("$script" 2>/tmp/s150_stderr_badusage.$$)"
status_badusage=$?
stderr_badusage="$(cat /tmp/s150_stderr_badusage.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_badusage.$$
[ "$status_badusage" -eq 2 ] || fail "S150 F5 — expected exit 2 with no PR number given, got $status_badusage"
[ -z "$output_badusage" ] || fail "S150 F5 — expected empty stdout on bad usage, got: $output_badusage"
[ -n "$stderr_badusage" ] || fail "S150 F5 — expected a usage message on stderr"

test_done
