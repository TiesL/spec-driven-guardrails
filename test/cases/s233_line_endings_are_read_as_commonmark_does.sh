#!/usr/bin/env bash
# S233 — CRLF and a lone CR are line endings: the CRLF body reads as the same body with LF, and a lone CR is a line break.
# Covers: F34
#
# Issue #423 AC5 (slice V2 of #411; A31a "Lines": before any matching, CRLF
# becomes LF and a lone CR becomes LF, as CommonMark reads them; this replaces
# A32's "remove every CR byte", under which a lone CR glued two markers into
# one line). Today's live_text keeps the CR, so a CRLF fence's closing line is
# "```\r" and never closes (the info-string rule sees the CR), and a marker
# after it is lost.
# Seam: lib/markdown.sh live_text and md_strip_fences under LC_ALL=C; exact
# outputs. A CR inside a value splits the line (a near-miss for the later
# record reader, never a silently cleaned value: here only the split is
# asserted). MD_LIB: scratch copy for mutations.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/markdown-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/markdown-helpers.sh"
sandbox_create
trap sandbox_destroy EXIT

NL=$'\n'
CR="$MD_CR"
M1='<!-- model-record: stage=Test model="ONE" effort="low" -->'
M2='<!-- model-record: stage=Review model="TWO" effort="low" -->'
BT='```'

# --- CRLF around a fence and a marker ---------------------------------------
lf="before${NL}${BT}${NL}${M1}${NL}${BT}${NL}${M2}${NL}after"
crlf="before${CR}${NL}${BT}${CR}${NL}${M1}${CR}${NL}${BT}${CR}${NL}${M2}${CR}${NL}after"
want="before${NL}${NL}${NL}${NL}${M2}${NL}after"
md_expect "S233 c1 LF baseline" live_text "$lf" "$want"
md_expect "S233 c1 CRLF body reads as the LF body" live_text "$crlf" "$want"
md_expect "S233 c1 CRLF body, md_strip_fences" md_strip_fences "$crlf" "before${NL}${NL}${NL}${NL}${M2}${NL}after"
md_run_lib C live_text "$crlf"
md_has_cr "$MD_OUT" && fail "S233 c1 — the output of a CRLF body must not hold a CR byte: $(printf '%q' "$MD_OUT")"
# a CRLF body ending in CRLF
md_expect "S233 c2 trailing CRLF" live_text "${M1}${CR}${NL}${M2}${CR}${NL}" "${M1}${NL}${M2}"
# a CRLF blockquote line, then a live marker
md_expect "S233 c3 CRLF blockquote" live_text "> quoted ${M1}${CR}${NL}${M2}" "${NL}${M2}"

# --- a lone CR is a line break ----------------------------------------------
md_expect "S233 d1 a lone CR between two markers: two lines" live_text "${M1}${CR}${M2}" "${M1}${NL}${M2}"
md_run_lib C live_text "${M1}${CR}${M2}"
[ "$(md_lines "$MD_OUT")" = "2" ] || fail "S233 d1 — a lone CR between two markers must give two lines, got $(md_lines "$MD_OUT"): $(printf '%q' "$MD_OUT")"
md_expect "S233 d1 md_strip_fences" md_strip_fences "${M1}${CR}${M2}" "${M1}${NL}${M2}"
# a fence whose every line ends in a lone CR is a fence
md_expect "S233 d2 a fence made of lone-CR lines" live_text "${BT}${CR}${M1}${CR}${BT}${CR}${M2}" "${NL}${NL}${NL}${M2}"
# mixed endings in one body, and a lone CR at the very end
md_expect "S233 d3 mixed CRLF and lone CR" live_text "a${CR}${NL}b${CR}c${CR}" "a${NL}b${NL}c"
# a CR inside a value splits the line
md_expect "S233 d4 a CR inside a value splits the line" live_text "<!-- model-record: stage=Test model=\"a${CR}b\" -->" "<!-- model-record: stage=Test model=\"a${NL}b\" -->"
# R: no CR at all: unchanged
md_expect "S233 R-d5 an LF body is unchanged" live_text "${M1}${NL}${M2}" "${M1}${NL}${M2}"

test_done
