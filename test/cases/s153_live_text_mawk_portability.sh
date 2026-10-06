#!/usr/bin/env bash
# S153 — live_text() has one definition, and its fence-detection is portable: the golden fence cases give the same answer under mawk and under /usr/bin/awk.
# Covers: F34, F35
#
# Issue #319 (original): the `^ {0,3}(`{3,}|~{3,})` regex made mawk's
# REcompile() panic (an unbounded-lower-bound interval combined with
# alternation in a group), `{n,}` alone is not greedy under mawk (it matches
# exactly n, silently truncating a longer fence run), and `{0,3}` does not
# parse at all on mawk 1.3.4 20200120 (Ubuntu 22.04's default `awk`): no
# fence is ever detected there. None of these show under gawk, so a run under
# gawk alone can never catch a regression: the golden cases run under mawk
# specifically, and, since #423, under /usr/bin/awk named explicitly (BWK awk
# on macOS, where #397's defects showed; whatever the distribution links
# elsewhere).
#
# Rewritten for #423 (slice V2 of #411, AC1 and AC6): the three verbatim
# copies of live_text() (compliance-evidence.sh, role-label-staleness.sh,
# model-record-gate.sh) are gone. There is ONE definition, in lib/markdown.sh,
# and the three scripts get it through lib/model-record.sh. The arm that
# asserted "the copies are byte-identical" is RETIRED with the copies; the
# arm that asserts there is exactly one definition replaces it. The golden
# cases G1-G6 are kept verbatim and now run against lib/markdown.sh; G7-G9 are
# new and put the new awk code (the list-item prefix, the backtick info
# string, CR splitting) through the same two awks, since a regex that is
# fine under gawk can still be unportable (brace intervals, `{n,}`).
#
# Fails loudly (not a skip) if mawk or /usr/bin/awk is missing: a runner
# without the exact interpreter this test exists to exercise must not report
# a vacuous green. mawk is a `./check` prerequisite (Debian/Ubuntu ship it;
# the macOS leg installs it for this scenario only).
# MD_LIB points at a scratch copy of lib/markdown.sh (mutation proof).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

lib="${MD_LIB:-$TEST_REPO_ROOT/lib/markdown.sh}"

# --- AC1: one definition ------------------------------------------------------
# Every text file but the docs, the test tree and .git: the only definition of
# live_text or md_strip_fences is lib/markdown.sh. Executable files without a
# .sh extension are covered (the search is by content, not by name).
def_ere='^[[:space:]]*(function[[:space:]]+)?(live_text|md_strip_fences)[[:space:]]*(\(\))?[[:space:]]*\{'
defs="$(cd "$TEST_REPO_ROOT" && LC_ALL=C grep -rIlE --exclude-dir=.git --exclude-dir=test --exclude-dir=wip --exclude='*.md' -e "$def_ere" . | LC_ALL=C sort)"
if [ "$defs" != "./lib/markdown.sh" ]; then
  fail "S153 — live_text()/md_strip_fences() must be defined only in lib/markdown.sh; files defining either: $(printf '%s' "$defs" | tr '\n' ' ')"
fi
for fn in live_text md_strip_fences; do
  LC_ALL=C grep -aqE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*(\(\))?[[:space:]]*\{" "$TEST_REPO_ROOT/lib/markdown.sh" \
    || fail "S153 — lib/markdown.sh does not define $fn"
done
# the three scripts reach it through lib/model-record.sh: after sourcing that
# one file, both functions are defined and their source file is markdown.sh
# shellcheck disable=SC2016  # the program text is meant to expand in the child
decl="$(env LC_ALL=C bash -c 'shopt -s extdebug; . "$1"; declare -F live_text md_strip_fences' _ "$TEST_REPO_ROOT/lib/model-record.sh" 2>/dev/null)"
for fn in live_text md_strip_fences; do
  case "$(LC_ALL=C grep -a "^$fn " <<<"$decl")" in
    *"/markdown.sh") : ;;
    *) fail "S153 — sourcing lib/model-record.sh alone must define $fn from lib/markdown.sh; declare -F says: '$(LC_ALL=C grep -a "^$fn " <<<"$decl")'" ;;
  esac
done

# --- the awks -----------------------------------------------------------------
if ! command -v mawk >/dev/null 2>&1; then
  fail "S153 — mawk not installed; cannot verify live_text() is mawk-portable (issue #319's own regression class)"
  test_done
fi
if [ ! -x /usr/bin/awk ]; then
  fail "S153 — /usr/bin/awk is missing; the cases must name it explicitly (BWK awk on macOS)"
  test_done
fi
echo "  S153: mawk: $(mawk -W version 2>&1 | head -1)"
echo "  S153: /usr/bin/awk: $(/usr/bin/awk --version 2>&1 | head -1)"

sandbox_create
trap sandbox_destroy EXIT

mawk_shim="$SANDBOX/mawk-shim"
mkdir -p "$mawk_shim"
ln -sf "$(command -v mawk)" "$mawk_shim/awk"
usr_shim="$SANDBOX/usr-bin-awk-shim"
mkdir -p "$usr_shim"
ln -sf /usr/bin/awk "$usr_shim/awk"

[ -f "$lib" ] || { fail "S153 — $lib is missing"; test_done; }
# shellcheck disable=SC1090
. "$lib"
declare -F live_text >/dev/null || { fail "S153 — $lib defines no live_text"; test_done; }

# Static guard against a regression to brace-interval syntax (`{0,3}`, `{3,}`)
# in a fence regex (PR #325, round 2): CI's mawk parses brace intervals fine,
# so a revert would pass every golden case below there and fail only on the
# older mawk build CI does not run. Unconditional, on every runner.
if LC_ALL=C grep -aqE 'match\([a-z_]+, /\^[^/]*\{[0-9]+,' "$lib"; then
  fail "S153 — lib/markdown.sh's fence regex has regressed to brace-interval syntax (\`{n,m}\`); use \`? ? ?\` (issue #319): the golden cases alone would NOT catch this on a runner whose awk parses brace intervals"
fi

# Golden fence scenarios, each run through the REAL, extracted live_text()
# from the given script, under a PATH where `awk` resolves to mawk. Every
# expected output already matches gawk's behavior (spot-checked by hand
# against the unpatched, pre-#319 gawk run) — the point isn't "what does
# mawk do", it's "mawk now agrees with gawk".
run_golden_cases() {
  local shim="$1" label="$2"

  # G1 — a simple 3-backtick fence: content inside stays blank, content
  # outside is untouched.
  local g1_in g1_out g1_expected
  g1_in=$'before\n```\nfenced content with `code`\n```\nafter'
  g1_expected=$'before\n\n\n\nafter'
  g1_out="$(PATH="$shim:$PATH" live_text "$g1_in")"
  [ "$g1_out" = "$g1_expected" ] || fail "S153 G1 ($label) — simple fence under $label: expected $(printf '%q' "$g1_expected"), got $(printf '%q' "$g1_out")"

  # G2 — a 5-tilde wrapper fence around an inner, non-fence line that
  # itself contains 3 backticks: the regression this issue exists to
  # catch. Under the panicking/truncating regex, mawk would either abort
  # outright or misjudge the wrapper's own length (flen).
  local g2_in g2_out g2_expected
  g2_in=$'before\n~~~~~\ninner not a real fence: ```demo```\n~~~~~\nafter'
  g2_expected=$'before\n\n\n\nafter'
  g2_out="$(PATH="$shim:$PATH" live_text "$g2_in")"
  [ "$g2_out" = "$g2_expected" ] || fail "S153 G2 ($label) — 5-char wrapper fence under $label: expected $(printf '%q' "$g2_expected"), got $(printf '%q' "$g2_out")"

  # G3 — D5/D6: a shorter closing run (3 backticks) must NOT close a
  # longer opening run (5 backticks) — this is exactly where the
  # non-greedy-under-mawk truncation bug would silently corrupt flen (a
  # truncated flen=3 would wrongly let the 3-backtick line close it).
  local g3_in g3_out g3_expected
  g3_in=$'before\n`````\nstill inside\n```\nstill inside too\n`````\nafter'
  g3_expected=$'before\n\n\n\n\n\nafter'
  g3_out="$(PATH="$shim:$PATH" live_text "$g3_in")"
  [ "$g3_out" = "$g3_expected" ] || fail "S153 G3 ($label) — shorter-close-must-not-close-longer-open under $label: expected $(printf '%q' "$g3_expected"), got $(printf '%q' "$g3_out")"

  # G4 — a real model-record marker survives past a same-length closed
  # fence, end to end (the actual thing every caller of live_text() uses
  # this function for).
  local g4_in g4_out
  g4_in=$'```\nsome demo content\n```\n<!-- model-record: stage=Review model="x" effort="low" -->'
  g4_out="$(PATH="$shim:$PATH" live_text "$g4_in")"
  grep -q 'model-record' <<<"$g4_out" || fail "S153 G4 ($label) — a real marker after a closed fence must stay live under $label"

  # G5 — the `length(m) >= 3` guard (issue #319, review round 1): a line
  # that starts with a 1- or 2-backtick inline-code run is not a fence
  # (CommonMark fences need >= 3). Without the guard, `+` alone matches
  # that short run too, opens a fence that never closes, and blanks
  # every line after it — including a real marker on a later line, which
  # is exactly the false "not-evidenced" this guard exists to prevent.
  local g5_in g5_out
  g5_in=$'`x` is inline code, not a fence\n<!-- model-record: stage=Review model="x" effort="low" -->'
  g5_out="$(PATH="$shim:$PATH" live_text "$g5_in")"
  grep -q 'model-record' <<<"$g5_out" || fail "S153 G5 ($label) — a 1-backtick run starting a line must not open a fence and swallow a later marker under $label"

  # G6 — a real fence-syntax line of one character (backtick) appearing
  # INSIDE an already-open fence of the OTHER character (tilde): must
  # stay blanked as ordinary fenced content, neither opening a nested
  # fence nor closing the outer one. This is the "real fence inside a
  # fence" case G2 never exercised (G2's inner line never starts with
  # backticks, so it never reaches the fence check at all).
  local g6_in g6_out g6_expected
  g6_in=$'before\n~~~~~\n```\nstill inside\n~~~~~\nafter'
  g6_expected=$'before\n\n\n\n\nafter'
  g6_out="$(PATH="$shim:$PATH" live_text "$g6_in")"
  [ "$g6_out" = "$g6_expected" ] || fail "S153 G6 ($label) — backtick fence-line nested inside an open tilde fence under $label: expected $(printf '%q' "$g6_expected"), got $(printf '%q' "$g6_out")"

  # G7 — a fence opened on a list-item line (#423, AC4): the closing line is
  # indented, so it must close the fence and not open a false one that hides
  # the column-0 marker after it. brace-free list-prefix regex under this awk.
  local g7_in g7_out g7_expected
  g7_in=$'- ```\n  inside\n  ```\n<!-- model-record: stage=Test model="x" effort="low" -->'
  g7_expected=$'\n\n\n<!-- model-record: stage=Test model="x" effort="low" -->'
  g7_out="$(PATH="$shim:$PATH" live_text "$g7_in")"
  [ "$g7_out" = "$g7_expected" ] || fail "S153 G7 ($label) — list-item fence: expected $(printf '%q' "$g7_expected"), got $(printf '%q' "$g7_out")"

  # G8 — a backtick fence line whose info string holds a backtick is not an
  # opener (#423, AC4): a marker after it is live.
  local g8_in g8_out
  g8_in=$'``` not `a fence\n<!-- model-record: stage=Test model="x" effort="low" -->'
  g8_out="$(PATH="$shim:$PATH" live_text "$g8_in")"
  grep -q 'model-record' <<<"$g8_out" || fail "S153 G8 ($label) — a backtick in a backtick fence's info string must not open a fence; got $(printf '%q' "$g8_out")"

  # G9 — CRLF and a lone CR are line endings (#423, AC5), through this awk's
  # own CR handling: the CRLF fence closes, the lone CR splits two lines.
  local g9_in g9_out g9_expected
  g9_in=$'```\r\nfenced\r\n```\r\nafter\rsecond'
  g9_expected=$'\n\n\nafter\nsecond'
  g9_out="$(PATH="$shim:$PATH" live_text "$g9_in")"
  [ "$g9_out" = "$g9_expected" ] || fail "S153 G9 ($label) — CRLF fence and lone CR: expected $(printf '%q' "$g9_expected"), got $(printf '%q' "$g9_out")"
}

run_golden_cases "$mawk_shim" "mawk"
run_golden_cases "$usr_shim" "/usr/bin/awk"

test_done
