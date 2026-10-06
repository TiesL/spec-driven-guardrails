#!/usr/bin/env bash
# S244 — a record in quoted text is `quoted`, never ok; a record not on a line of its own is a near-miss; non-candidates print nothing (R3)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC1 (every wrapped row is quoted), AC2/AC6 (a
# record after an unclosed fence is quoted; the fence does not leak into the
# next body); A31a (the class table: ok, near-miss, quoted; column 0; an
# unclosed fence runs to the end of its body), #308 and #400 (a quoted marker
# is not evidence). Seam: rec_scan rows only (class and order), plus rec_field
# on the ok rows.
#
# Oracle per shape (the QA critique D12 asked for one, not a blanket rule).
# The fence shapes were labelled ONCE against GitHub's renderer on 2026-10-06
# (gh api markdown, mode gfm: a live comment is dropped from the HTML, a quoted
# one comes back as &lt;!-- ...). The policy shapes are decided by A31a, not
# by the renderer, and say so:
#   fence (backtick, tilde, longer closer, info string, 3-space indent) quoted  (GitHub: quoted)
#   unclosed fence, record after it                                      quoted  (GitHub: quoted)
#   fence closed, record after it                                        ok      (GitHub: live)
#   closing line with an info string does not close; ~~~ does not close ```     quoted (GitHub: quoted)
#   backtick fence whose info string holds a backtick is NOT an opener  ok      (GitHub: live; PRD debt row closed by A32a)
#   tilde fence whose info string holds a backtick IS an opener          quoted  (GitHub: quoted)
#   list-item fence ("1. ```", "- ```")                                  quoted  (GitHub: quoted)
#   4-space indented fence line is not a fence                           ok after (GitHub: live)
#   code span                                                            quoted  (GitHub: quoted)
#   blockquote, 4+ spaces or a tab of indent                             quoted  (policy A31a; GitHub shows a blockquoted comment as hidden)
#   1-3 leading spaces, inline after prose, table cell, list-item line   near-miss (policy A31a: not a line of its own)
#
# Threat model: ACCIDENTAL quoting defects (#308, #400, #405 round 4): an
# example of a record in a design comment read as a live record. A deliberate
# forger who types a strict line at column 0 outside any quoting is not
# stopped here; that is the limit A34a states.
#
# Red today: stubs (return 99). Mutations this case must not survive (kill
# table): drop the fence strip from rec_scan; read a record inside a fence;
# let fence state cross a body in the bundle (S245); treat 1-3 leading spaces as
# column 0; accept a 4-space indent; read a code span; treat a backtick-info
# line as a fence opener; close a fence on a closer with an info string; close
# a ``` fence on a ~~~ line.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S244" || test_done

R='<!-- model-record: stage=Test model="m1" -->'
S='<!-- model-record: stage=Review model="sentinel" floor-basis="f" -->'
LF=$'\n'
TAB=$'\t'

# check <label> <want classes> <body> [kind]
check() {
  local label="$1" want="$2" body="$3" kind="${4:-model-record}" mode
  for mode in $RH_MODES; do
    rh_scan "S244/$label" "$mode" "$kind" "$body" || continue
    [ "$(rh_classes)" = "$want" ] || fail "S244/$label [$mode] — want classes '$want', got '$(rh_classes)'"
    # an ok row holds one of the lines of the body, verbatim
    local i=0
    while [ "$i" -lt "$RH_N" ]; do
      if [ "${RH_CLS[$i]}" = ok ]; then
        case "$body" in
          *"${RH_TXT[$i]}"*) : ;;
          *) fail "S244/$label [$mode] — an ok row holds '${RH_TXT[$i]}', which is not a line of the body" ;;
        esac
      fi
      i=$((i + 1))
    done
  done
}

# --- fences (GitHub-labelled) -------------------------------------------------
check "backtick fence" "quoted" "\`\`\`${LF}${R}${LF}\`\`\`"
check "tilde fence" "quoted" "~~~${LF}${R}${LF}~~~"
check "longer closing run" "quoted" "\`\`\`${LF}${R}${LF}\`\`\`\`\`"
check "info string on the opener" "quoted" "\`\`\`text${LF}${R}${LF}\`\`\`"
check "three-space indented fence" "quoted" "   \`\`\`${LF}${R}${LF}   \`\`\`"
check "four-backtick fence, a shorter inner run does not close it" "quoted quoted" "\`\`\`\`${LF}${R}${LF}\`\`\`${LF}${R}${LF}\`\`\`\`"
check "a different fence character does not close" "quoted quoted" "\`\`\`${LF}${R}${LF}~~~${LF}${R}"
check "a closing line with an info string does not close" "quoted" "\`\`\`${LF}x${LF}\`\`\`text${LF}${R}${LF}\`\`\`"
check "unclosed fence, the record after it is quoted" "quoted" "x${LF}${LF}\`\`\`${LF}foo${LF}${LF}${R}"
check "unclosed fence runs to the end of the body, later records too" "quoted quoted" "\`\`\`${LF}${R}${LF}${S}"
check "a closed fence ends the quoting" "ok" "\`\`\`${LF}foo${LF}\`\`\`${LF}${R}"
check "a record before, inside and after a fence" "ok quoted ok" "${R}${LF}\`\`\`${LF}${R}${LF}\`\`\`${LF}${S}"
check "backtick fence whose info string holds a backtick is not an opener" "ok" "\`\`\`x\` y${LF}${R}"
check "tilde fence whose info string holds a backtick is an opener" "quoted" "~~~x\` y${LF}${R}${LF}~~~"
check "ordered list-item fence" "quoted" "1. \`\`\`${LF}   ${R}${LF}   \`\`\`"
check "bullet list-item fence, then a live record" "quoted ok" "- \`\`\`${LF}  ${R}${LF}  \`\`\`${LF}${LF}${S}"
check "a four-space indented fence line is no fence" "ok" "    \`\`\`${LF}${R}"
check "CRLF endings around a fence" "quoted ok" "\`\`\`"$'\r'"${LF}${R}"$'\r'"${LF}\`\`\`"$'\r'"${LF}${S}"$'\r'

# --- spans, blockquotes, indentation (A31a) ------------------------------------
check "code span" "quoted" "\`${R}\`"
check "code span inside prose" "quoted" "Write \`${R}\` yourself? No: use the emitter."
check "double-backtick span holding a backtick" "quoted" "\`\`<!-- model-record: stage=Test model=\"m1\" \`x\` -->\`\`"
check "blockquote" "quoted" "> ${R}"
check "blockquote, three spaces in" "quoted" "   > ${R}"
check "nested blockquote" "quoted" ">> ${R}"
check "four spaces of indent" "quoted" "    ${R}"
check "a tab of indent" "quoted" "${TAB}${R}"
check "a live record after each of the quoted shapes" "quoted ok quoted ok quoted ok" "> ${R}${LF}${S}${LF}    ${R}${LF}${S}${LF}\`${R}\`${LF}${S}"

# --- not on a line of its own: near-miss (A31a) --------------------------------
check "one leading space" "near-miss" " ${R}"
check "three leading spaces" "near-miss" "   ${R}"
check "inline after prose" "near-miss" "Done. ${R}"
check "inline before prose" "near-miss" "${R} Done."
check "table cell" "near-miss" "| a | ${R} |"
check "list-item line" "near-miss" "- ${R}"
check "numbered list-item line" "near-miss" "1. ${R}"
check "an unmatched backtick is literal text, the opener is live and inline" "near-miss" "\`${R}"
check "a span before and a live opener after it" "near-miss" "\`x\` ${R}"

# --- not a candidate: no row at all ---------------------------------------------
NBSP="$(printf '\302\240')"
ZW="$(printf '\342\200\213')"
check "NBSP between <!-- and model-record: is plain text (stated limit)" "" "<!--${NBSP}model-record: stage=Test model=\"m1\" -->"
check "a zero-width space between <!-- and model-record: is plain text (stated limit)" "" "<!--${ZW}model-record: stage=Test model=\"m1\" -->"
check "a different comment that starts with the word" "" "<!-- model-record-gate: x -->"
check "no colon after model-record" "" "<!-- model-record stage=Test model=\"m1\" -->"
check "a finding marker that mentions the word" "" "<!-- finding:no-model-record status=open -->"
check "bare prose without a comment opener" "" "every PR needs a model-record: stage=Test marker"
check "an opener with no model-record at all" "" "<!-- nfr: x -->"

# --- the second kind obeys the same rules ---------------------------------------
PO='<!-- pipeline-override: decided-by="human" scope="single-session" reason="r" -->'
check "override in a fence" "quoted" "\`\`\`${LF}${PO}${LF}\`\`\`" pipeline-override
check "override in a span" "quoted" "Write \`${PO}\` yourself" pipeline-override
check "override in a blockquote" "quoted" "> ${PO}" pipeline-override
check "override indented four spaces" "quoted" "    ${PO}" pipeline-override
check "override inline" "near-miss" "Waived. ${PO}" pipeline-override
check "override live" "ok" "${PO}" pipeline-override
check "override with > in the reason is a near-miss" "near-miss" '<!-- pipeline-override: decided-by="human" scope="single-session" reason="a > b" -->' pipeline-override

# --- AC1's wrap: any record line inside a fence one character longer than its
# longest backtick run is quoted, under every locale environment ---------------
wraps=(
  "$R"
  "$S"
  "<!-- model-record: stage=Review model=\"m1\" floor-basis=\"has a \`\`\` run and a \` tick\" -->"
  "<!-- model-record: stage=Review model=\"m1\" floor-basis=\"\`\`\`\`\` five ticks\" -->"
  "Done. $R"
  "> $R"
  "${R}  "
  "$(printf '<!-- model-record: stage=Review model="m1" floor-basis="a\377b" -->')"
)
for w in "${wraps[@]}"; do
  longest=0
  rest="$w"
  while [ -n "$rest" ]; do
    case "$rest" in
      '`'*)
        run=0
        while [ "${rest#'`'}" != "$rest" ]; do
          rest="${rest#'`'}"
          run=$((run + 1))
        done
        [ "$run" -le "$longest" ] || longest="$run"
        ;;
      *) rest="${rest#?}" ;;
    esac
  done
  fence="\`\`\`"
  while [ "${#fence}" -le "$longest" ]; do fence="$fence\`"; done
  check "wrapped in a $((${#fence}))-backtick fence: ${w:0:40}" "quoted" "${fence}${LF}${w}${LF}${fence}"
  tfence="~~~"
  check "wrapped in a tilde fence: ${w:0:40}" "quoted" "${tfence}${LF}${w}${LF}${tfence}"
done

test_done
