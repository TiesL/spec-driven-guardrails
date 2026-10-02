#!/usr/bin/env bash
# S153 — live_text()'s fence-detection regex is mawk-portable.
# Covers: F34, F35
#
# Issue #319: the original `^ {0,3}(`{3,}|~{3,})` regex made mawk's
# REcompile() panic outright (an unbounded-lower-bound interval combined
# with alternation in a group), and separately, `{n,}` alone is not
# greedy under mawk — it matches exactly n, not "n or more" — silently
# truncating a longer fence run and corrupting the recorded fence length
# even where it didn't panic. A second, independent defect found in the
# same issue's later review round: `{0,3}` itself doesn't parse at all
# on an older mawk build (1.3.4 20200120, the default `awk` on Ubuntu
# 22.04) — it's read as four literal characters, so no fence is ever
# detected there, silently. None of these failure modes show up under
# gawk, so a test run under gawk alone (this repo's usual CI/local awk)
# can never catch a regression here — this test specifically
# re-extracts the real, shipped `live_text()` from both files that
# carry a copy of it and runs it under mawk, the same "no stale copy"
# technique s151_compliance_evidence_quoting.sh's Q21-Q23 already use
# for CALL_A_JQ/live_text() under gawk.
#
# Fails loudly (not a skip) if mawk isn't installed — same discipline
# as S151's own jq-availability check, and this repo's convention for a
# missing hard prerequisite: a runner without the exact interpreter this
# test exists to exercise must not report a vacuous green. mawk is a
# `./check` prerequisite as of this test; it ships by default on
# Debian/Ubuntu but not on macOS or Fedora.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

if ! command -v mawk >/dev/null 2>&1; then
  fail "S153 — mawk not installed; cannot verify live_text() is mawk-portable (issue #319's own regression class)"
  test_done
fi

mawk_version="$(mawk -W version 2>&1 | head -1)"
echo "  S153: running under $mawk_version"

sandbox_create
trap sandbox_destroy EXIT

mawk_shim="$SANDBOX/mawk-shim"
mkdir -p "$mawk_shim"
ln -sf "$(command -v mawk)" "$mawk_shim/awk"

# The two files carry independently-copied bodies of live_text() by this
# repo's own "dogfood-only boundary" convention (compliance-evidence.sh
# is dogfood-only; role-label-staleness.sh ships to adopted projects via
# adopt.sh, so a shared lib would cross that boundary) — but a copy that
# silently drifts from its sibling is exactly the kind of thing this
# scenario exists to catch. Asserting the two extracted bodies are
# byte-identical enforces that convention directly, not just implicitly
# through the golden cases below.
body_a="$(awk '/^live_text\(\) \{/,/^}/' "$TEST_REPO_ROOT/compliance-evidence.sh")"
body_b="$(awk '/^live_text\(\) \{/,/^}/' "$TEST_REPO_ROOT/role-label-staleness.sh")"
[ -n "$body_a" ] || fail "S153 — extracting live_text() from compliance-evidence.sh produced nothing"
[ -n "$body_b" ] || fail "S153 — extracting live_text() from role-label-staleness.sh produced nothing"
[ "$body_a" = "$body_b" ] || fail "S153 — live_text() has drifted between compliance-evidence.sh and role-label-staleness.sh (must be copied verbatim)"
# #371: model-record-gate.sh (installed in adopted projects) carries a
# third copy for its role-play check; same rule, same byte-identity.
body_c="$(awk '/^live_text\(\) \{/,/^}/' "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh")"
[ "$body_a" = "$body_c" ] || fail "S153 — live_text() has drifted between compliance-evidence.sh and skills/pre-merge-review/model-record-gate.sh (must be copied verbatim)"

# Static guard against a regression back to brace-interval syntax
# (`{0,3}`, `{3,}`) in the fence regex, found during PR #325's own
# review round 2: CI's own mawk (1.3.4 20240123) parses brace intervals
# just fine, so a revert of the `? ? ?` fix back to `{0,3}` would still
# pass every golden case below on CI, and would only fail on the older
# mawk build (1.3.4 20200120, e.g. Ubuntu 22.04's default `awk`) that
# CI doesn't run on — exactly the silent, environment-dependent gap
# issue #319 exists to close. This check is unconditional (not run
# under mawk specifically) precisely because it must catch the
# regression on every runner, including this container's own newer mawk
# and gawk, neither of which would otherwise notice.
if grep -qE 'match\(line, /\^[^/]*\{[0-9]+,' <<<"$body_a$body_b$body_c"; then
  fail "S153 — live_text()'s fence regex has regressed to brace-interval syntax (\`{n,m}\`); replace with \`? ? ?\` (issue #319) — this would NOT be caught by the golden cases alone on a runner whose mawk happens to support brace intervals"
fi

# Golden fence scenarios, each run through the REAL, extracted live_text()
# from the given script, under a PATH where `awk` resolves to mawk. Every
# expected output already matches gawk's behavior (spot-checked by hand
# against the unpatched, pre-#319 gawk run) — the point isn't "what does
# mawk do", it's "mawk now agrees with gawk".
run_golden_cases() {
  local script="$1" label="$2"

  # unset first (finding: s153-stale-definition-leak) — without this, a
  # broken/missing extraction from $script would silently re-run the
  # PREVIOUS iteration's still-defined live_text() a second time and
  # report a false green. Confirmed: renaming live_text() in one file
  # and restoring the old panicking regex there used to leave this test
  # green anyway, because it kept re-testing the other file's copy.
  unset -f live_text
  eval "$(awk '/^live_text\(\) \{/,/^}/' "$script")"
  declare -F live_text >/dev/null || {
    fail "S153 ($label) — extracting live_text() from $script produced no callable function"
    return
  }

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

  # G5 — the `length(m) >= 3` guard (issue #319, review round 1): a line
  # that starts with a 1- or 2-backtick inline-code run is not a fence
  # (CommonMark fences need >= 3). Without the guard, `+` alone matches
  # that short run too, opens a fence that never closes, and blanks
  # every line after it — including a real marker on a later line, which
  # is exactly the false "not-evidenced" this guard exists to prevent.
  local g5_in g5_out
  g5_in=$'`x` is inline code, not a fence\n<!-- model-record: stage=Review model="x" effort="low" -->'
  g5_out="$(PATH="$mawk_shim:$PATH" live_text "$g5_in")"
  grep -q 'model-record' <<<"$g5_out" || fail "S153 G5 ($label) — a 1-backtick run starting a line must not open a fence and swallow a later marker under mawk"

  # G6 — a real fence-syntax line of one character (backtick) appearing
  # INSIDE an already-open fence of the OTHER character (tilde): must
  # stay blanked as ordinary fenced content, neither opening a nested
  # fence nor closing the outer one. This is the "real fence inside a
  # fence" case G2 never exercised (G2's inner line never starts with
  # backticks, so it never reaches the fence check at all).
  local g6_in g6_out g6_expected
  g6_in=$'before\n~~~~~\n```\nstill inside\n~~~~~\nafter'
  g6_expected=$'before\n\n\n\n\nafter'
  g6_out="$(PATH="$mawk_shim:$PATH" live_text "$g6_in")"
  [ "$g6_out" = "$g6_expected" ] || fail "S153 G6 ($label) — backtick fence-line nested inside an open tilde fence under mawk: expected $(printf '%q' "$g6_expected"), got $(printf '%q' "$g6_out")"
}

run_golden_cases "$TEST_REPO_ROOT/compliance-evidence.sh" "compliance-evidence.sh"
run_golden_cases "$TEST_REPO_ROOT/role-label-staleness.sh" "role-label-staleness.sh"

test_done
