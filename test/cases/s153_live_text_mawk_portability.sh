#!/usr/bin/env bash
# S153 — live_text()'s fence-detection regex is mawk-portable.
# Covers: F34, F35
#
# Issue #319: the original `^ {0,3}(`{3,}|~{3,})` regex made mawk's
# REcompile() panic outright (an unbounded-lower-bound interval combined
# with alternation in a group), and separately, `{n,}` alone is not
# greedy under mawk — it matches exactly n, not "n or more" — silently
# truncating a longer fence run and corrupting the recorded fence length
# even where it didn't panic. Neither failure mode shows up under gawk,
# so a test run under gawk alone (this repo's usual CI/local awk) can
# never catch a regression here — this test specifically re-extracts the
# real, shipped `live_text()` from both files that carry a copy of it and
# runs it under mawk, the same "no stale copy" technique
# s151_compliance_evidence_quoting.sh's Q21-Q23 already use for
# CALL_A_JQ/live_text() under gawk.
#
# Skips loudly (not silently) if mawk isn't installed — same discipline
# as S151's own jq-availability check: a runner without the exact
# interpreter this test exists to exercise must not report a vacuous
# green.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

if ! command -v mawk >/dev/null 2>&1; then
  fail "S153 — mawk not installed; cannot verify live_text() is mawk-portable (issue #319's own regression class)"
  test_done
fi

sandbox_create
trap sandbox_destroy EXIT

mawk_shim="$SANDBOX/mawk-shim"
mkdir -p "$mawk_shim"
ln -sf "$(command -v mawk)" "$mawk_shim/awk"

# Golden fence scenarios, each run through the REAL, extracted live_text()
# from the given script, under a PATH where `awk` resolves to mawk. Every
# expected output already matches gawk's behavior (spot-checked by hand
# against the unpatched, pre-#319 gawk run) — the point isn't "what does
# mawk do", it's "mawk now agrees with gawk".
run_golden_cases() {
  local script="$1" label="$2"
  eval "$(awk '/^live_text\(\) \{/,/^}/' "$script")"

  # G1 — a simple 3-backtick fence: content inside stays blank, content
  # outside is untouched.
  local g1_in g1_out g1_expected
  g1_in=$'before\n```\nfenced content with `code`\n```\nafter'
  g1_expected=$'before\n\n\n\nafter'
  g1_out="$(PATH="$mawk_shim:$PATH" live_text "$g1_in")"
  [ "$g1_out" = "$g1_expected" ] || fail "S153 G1 ($label) — simple fence under mawk: expected $(printf '%q' "$g1_expected"), got $(printf '%q' "$g1_out")"

  # G2 — a 5-tilde wrapper fence around an inner, non-fence line that
  # itself contains 3 backticks: the regression this issue exists to
  # catch. Under the panicking/truncating regex, mawk would either abort
  # outright or misjudge the wrapper's own length (flen).
  local g2_in g2_out g2_expected
  g2_in=$'before\n~~~~~\ninner not a real fence: ```demo```\n~~~~~\nafter'
  g2_expected=$'before\n\n\n\nafter'
  g2_out="$(PATH="$mawk_shim:$PATH" live_text "$g2_in")"
  [ "$g2_out" = "$g2_expected" ] || fail "S153 G2 ($label) — 5-char wrapper fence under mawk: expected $(printf '%q' "$g2_expected"), got $(printf '%q' "$g2_out")"

  # G3 — D5/D6: a shorter closing run (3 backticks) must NOT close a
  # longer opening run (5 backticks) — this is exactly where the
  # non-greedy-under-mawk truncation bug would silently corrupt flen (a
  # truncated flen=3 would wrongly let the 3-backtick line close it).
  local g3_in g3_out g3_expected
  g3_in=$'before\n`````\nstill inside\n```\nstill inside too\n`````\nafter'
  g3_expected=$'before\n\n\n\n\n\nafter'
  g3_out="$(PATH="$mawk_shim:$PATH" live_text "$g3_in")"
  [ "$g3_out" = "$g3_expected" ] || fail "S153 G3 ($label) — shorter-close-must-not-close-longer-open under mawk: expected $(printf '%q' "$g3_expected"), got $(printf '%q' "$g3_out")"

  # G4 — a real model-record marker survives past a same-length closed
  # fence, end to end (the actual thing every caller of live_text() uses
  # this function for).
  local g4_in g4_out
  g4_in=$'```\nsome demo content\n```\n<!-- model-record: stage=Review model="x" effort="low" -->'
  g4_out="$(PATH="$mawk_shim:$PATH" live_text "$g4_in")"
  grep -q 'model-record' <<<"$g4_out" || fail "S153 G4 ($label) — a real marker after a closed fence must stay live under mawk"
}

run_golden_cases "$TEST_REPO_ROOT/compliance-evidence.sh" "compliance-evidence.sh"
run_golden_cases "$TEST_REPO_ROOT/role-label-staleness.sh" "role-label-staleness.sh"

test_done
