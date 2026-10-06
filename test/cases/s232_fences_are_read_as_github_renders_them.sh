#!/usr/bin/env bash
# S232 — a fence opened on a list-item line is recognized, and a backtick fence whose info string holds a backtick is not an opener.
# Covers: F34
#
# Issue #423 AC4 (slice V2 of #411; A31a, A32a intended changes 2 and 3, as in
# CommonMark). Two defects of today's live_text:
#   (a) a fence opened on a list-item line ("- ```") is not seen, so its
#       indented CLOSING line is read as an OPENER and hides every later
#       column-0 marker: a false quoted, a real record lost;
#   (b) "``` has `a backtick`" is read as an opener, but CommonMark says the
#       info string of a backtick fence cannot contain a backtick; GitHub
#       renders that line as a paragraph, so a marker after it is live.
# Markers: INSIDE (indented, inside the list-item fence) is quoted; AFTER
# (column 0, after the closing line) is live. Architect's answer on #423
# (AC4 precision): the marker after the fence starts in column 0, outside the
# list item; the marker inside may be indented as list content is. NOT tested
# (A32b accepted limits): nested list prefixes, list items inside a blockquote,
# tab expansion beyond the tab rule. Where a list-item fence ENDS (the item
# ends it, A32b) is tested below, arms la-lh.
# The PR records `gh api markdown` output for these shapes once as evidence;
# it is not a CI oracle (A31a, Reviewer D2 rejected it).
# Seam: lib/markdown.sh live_text and md_strip_fences under LC_ALL=C; the
# expectations are exact outputs (blanked lines keep the line count).
# Regression arms (green on arrival once the lib exists, labelled R): the
# plain fence, a tilde fence with a backtick in its info string, a bullet line
# that merely mentions three backticks. MD_LIB: scratch copy for mutations.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/markdown-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/markdown-helpers.sh"
sandbox_create
trap sandbox_destroy EXIT

NL=$'\n'
IN='<!-- model-record: stage=Test model="INSIDE" effort="low" -->'
AF='<!-- model-record: stage=Review model="AFTER" effort="low" -->'
BT='```'

# --- (a) list-item fences ---------------------------------------------------
want="${NL}${NL}${NL}${AF}"
md_expect "S232 a1 bullet '-' fence" live_text "- ${BT}${NL}  ${IN}${NL}  ${BT}${NL}${AF}" "$want"
md_expect "S232 a1 bullet '-' fence" md_strip_fences "- ${BT}${NL}  ${IN}${NL}  ${BT}${NL}${AF}" "$want"
md_expect "S232 a2 bullet '*' fence with an info string" live_text "* ${BT}bash${NL}  ${IN}${NL}  ${BT}${NL}${AF}" "$want"
md_expect "S232 a3 bullet '+' tilde fence" live_text "+ ~~~${NL}  ${IN}${NL}  ~~~${NL}${AF}" "$want"
md_expect "S232 a4 ordered item '1.' fence (content column 3)" live_text "1. ${BT}${NL}   ${IN}${NL}   ${BT}${NL}${AF}" "$want"
md_expect "S232 a5 a fence in the second item, after a plain first item" live_text "- first${NL}- ${BT}${NL}  ${IN}${NL}  ${BT}${NL}${AF}" "- first${NL}${NL}${NL}${NL}${AF}"
md_expect "S232 a6 a longer closing run closes it (>= opener)" live_text "- ${BT}${NL}  ${IN}${NL}  \`\`\`\`${NL}${AF}" "$want"
md_expect "S232 a7 a shorter run inside does not close a longer list-item fence" live_text "- \`\`\`\`${NL}  ${IN}${NL}  ${BT}${NL}  ${IN}${NL}  \`\`\`\`${NL}${AF}" "${NL}${NL}${NL}${NL}${NL}${AF}"
# R: a bullet line that only MENTIONS three backticks opens nothing
md_expect "S232 R-a8 a bullet mentioning backticks is not a fence" live_text "- use ${BT} to fence${NL}${AF}" "- use ${BT} to fence${NL}${AF}"
# R: the plain column-0 fence
md_expect "S232 R-a9 plain fence" live_text "${BT}${NL}${IN}${NL}${BT}${NL}${AF}" "$want"
# two list-item fences in a row: neither closing line opens a false fence
md_expect "S232 a10 two list-item fences in a row" live_text "- ${BT}${NL}  ${IN}${NL}  ${BT}${NL}- ${BT}${NL}  ${IN}${NL}  ${BT}${NL}${AF}" "${NL}${NL}${NL}${NL}${NL}${NL}${AF}"

# --- (b) a backtick in the info string of a backtick fence -----------------
md_live "S232 b1 backtick in the info string is not an opener" "${BT} not \`a fence${NL}${AF}" "" "$AF"
md_live "S232 b2 same, indented 3 spaces" "   ${BT} x\`y${NL}${AF}" "" "$AF"
md_live "S232 b3 same, with four backticks" "\`\`\`\` x\`y${NL}${AF}" "" "$AF"
# the line is plain text, so what follows is live text, and a LATER bare run
# opens a fence that runs to the end of the body (A31a): IN is live, AFTER
# is quoted. This pins that the first line was neither an opener nor a closer.
md_live "S232 b4 a bare run after a non-opener line opens its own fence" "${BT} a\`b\`c${NL}${IN}${NL}${BT}${NL}${AF}" "AFTER" "INSIDE"
md_expect "S232 b5 md_strip_fences, same shape as b1" md_strip_fences "${BT} not \`a fence${NL}${AF}" "${BT} not \`a fence${NL}${AF}"
# R: a TILDE fence may carry a backtick in its info string and still opens
md_expect "S232 R-b6 tilde fence with a backtick in the info string" live_text "~~~ a\`b${NL}${IN}${NL}~~~${NL}${AF}" "$want"
# R: a backtick fence whose info string holds a tilde is an opener
md_expect "S232 R-b7 backtick fence, info string with a tilde" live_text "${BT}a~b${NL}${IN}${NL}${BT}${NL}${AF}" "$want"
# R: an opener with an ordinary info string
md_expect "S232 R-b8 ordinary info string" live_text "${BT}markdown${NL}${IN}${NL}${BT}${NL}${AF}" "$want"

# md_strip_fences is the fence logic only (A32): an inline code span is left
# as written, where live_text would drop it
md_expect "S232 e1 md_strip_fences leaves a code span alone" md_strip_fences "x \`span\` y${NL}${AF}" "x \`span\` y${NL}${AF}"
md_expect "S232 e2 live_text drops the same code span" live_text "x \`span\` y${NL}${AF}" "x   y${NL}${AF}"

# --- (c) where a list-item fence ENDS (A32b, review round 1 of PR #443) -------
# CommonMark: a list item ends at the first non-blank line indented less than
# its content column, and that ends its fence too (lazy continuation never
# applies to a fenced block). The ending line is then read as an ordinary
# top-level line: it can be live text (lb), or open a top-level fence (la, le).
# Blank and whitespace-only lines never end the item; a line whose leading
# whitespace holds a TAB never ends it (tabs are not expanded; keeping the
# fence open is the safe direction). Every expectation below was checked
# against `gh api markdown -f mode=gfm` on the day it was written (recorded
# evidence, not a CI oracle). Failing direction that matters: a recognizer
# that ends a fence EARLIER than GitHub does reads a quoted marker as live.
IN2='<!-- model-record: stage=Test model="INSIDE2" effort="low" -->'
TAB=$'\t'
# la: closed at column 0: the column-0 run ends the item and opens a top-level
# fence, so the marker after it is quoted (GitHub: <pre><code>AFTER)
md_expect "S232 la list fence 'closed' at column 0: the next column-0 line is quoted" live_text "- ${BT}${NL}  ${IN}${NL}${BT}${NL}${AF}" ""
md_expect "S232 la md_strip_fences, same shape" md_strip_fences "- ${BT}${NL}  ${IN}${NL}${BT}${NL}${AF}" ""
# lb: a column-0 line ends the item (live), a later column-0 run opens a
# top-level fence, so the second marker is quoted (GitHub: <p>M1</p> then code M2)
md_expect "S232 lb the column-0 line after the item is live, the one after a column-0 run quoted" live_text "- ${BT}${NL}  ${IN}${NL}${AF}${NL}${BT}${NL}${IN2}" "${NL}${NL}${AF}"
md_expect "S232 lb md_strip_fences, same shape" md_strip_fences "- ${BT}${NL}  ${IN}${NL}${AF}${NL}${BT}${NL}${IN2}" "${NL}${NL}${AF}"
# lc: an unclosed list fence: the item ends at the column-0 line, which is live
# (GitHub: <p>M1</p>); replaces the 'unspecified' of QA note 7
md_expect "S232 lc an unclosed list fence ends where its item ends" live_text "- ${BT}${NL}  ${IN}${NL}${AF}" "${NL}${NL}${AF}"
# ld: a blank line does not end the item (GitHub: IN1, IN2 in one code block, M1 a paragraph)
md_expect "S232 ld a blank line inside a list fence keeps it open" live_text "- ${BT}${NL}  ${IN}${NL}${NL}  ${IN2}${NL}  ${BT}${NL}${AF}" "${NL}${NL}${NL}${NL}${NL}${AF}"
# ld2: a whitespace-only line (one space, below the content column) does not end it either
md_expect "S232 ld2 a whitespace-only line below the content column keeps it open" live_text "- ${BT}${NL}  ${IN}${NL} ${NL}  ${IN2}${NL}  ${BT}${NL}${AF}" "${NL}${NL}${NL}${NL}${NL}${AF}"
# le: an ordered item (content column 3) whose 'closing' run is indented only 2: it
# ends the item and opens a top-level fence, so the marker after it is quoted
md_expect "S232 le a run indented below the content column ends the item and opens a fence" live_text "1. ${BT}${NL}   ${IN}${NL}  ${BT}${NL}${AF}" ""
# lf: a TAB-indented line inside does not end the item; the indent-2 run closes
md_expect "S232 lf a tab-indented line inside a list fence keeps it open" live_text "- ${BT}${NL}${TAB}${IN}${NL}  ${BT}${NL}${AF}" "${NL}${NL}${NL}${AF}"
# lg / lh: the closing line may be indented up to 3 PAST the content column:
# content column 3, a run at 6 closes; a run at 7 does not (GitHub: it stays code text)
md_expect "S232 lg a closing run indented content column + 3 closes the list fence (the item's next line is live)" live_text "1. ${BT}${NL}   ${IN}${NL}      ${BT}${NL}   ${IN2}${NL}${AF}" "${NL}${NL}${NL}   ${IN2}${NL}${AF}"
md_expect "S232 lh a run indented content column + 4 does not close it" live_text "1. ${BT}${NL}   ${IN}${NL}       ${BT}${NL}   ${IN2}${NL}${AF}" "${NL}${NL}${NL}${NL}${AF}"
# R: top-level fences are unchanged by the item-end rule (a column-0 fence has
# no content column): an indented line inside it never ends it
md_expect "S232 R-lr a top-level fence is not ended by an indented line" live_text "${BT}${NL}${IN}${NL}  x${NL}${BT}${NL}${AF}" "${NL}${NL}${NL}${NL}${AF}"

test_done
