#!/usr/bin/env bash
# S245 — rec_scan_bundle resets fence state per body, keeps body order and indices, and every row has four non-empty fields; same-stage records, CRLF, a lone CR and an override with `>` read as the issue says (R4 + AC6)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC6; A32a (a bundle is bodies each followed by
# U+001E, one awk pass for the whole bundle, fence state reset at every
# separator, output <body-index> TAB <class> TAB <stage-or-?> TAB <line-or-
# reason>, no field ever empty), A31a (CRLF becomes LF, a lone CR becomes LF,
# two records of one stage: the later line wins). Seam: rec_scan_bundle and
# rec_scan rows, and rec_field on the ok line.
#
# What "the later of two same-stage records wins" means at THIS seam: the reader
# prints every ok line in body order (it does not drop the earlier one: a
# caller such as the gate still reports presence from all of them), and the
# LAST ok row of a stage in a body, across a bundle the last body's last row,
# is the later record; reading that row's line gives the later fields. The
# pick-the-last rule is the caller's and is applied here by the helper below.
# (Design A34/A37 move the callers to it in V6 to V8; this slice only pins that
# the rows are there, in order, and exact.)
#
# Body indices count from 1. The design left the base open (A32a only says
# <body-index>); this test pins 1 and the issue's wording "body-index" follows
# awk's NR convention. A Developer who wants 0 changes this one test with the
# Architect, not silently.
#
# Threat model: ACCIDENTAL defects: state that leaks between bodies (#397
# round 3: one open quote, or here one unclosed fence, hiding the next body),
# CR handling that joins two records into one line (QA critique D12), an empty
# field that shifts a tab-split row, a row that carries a newline, an unbounded
# dump of a huge line into the reason. No forger is modelled.
#
# Red today: stubs (return 99). Mutations this case must not survive (kill
# table): run the scan on the concatenated bodies (fence leaks); drop the
# per-separator reset; renumber bodies after skipping empty ones; strip CR
# bytes instead of reading them as line ends (a lone CR then joins two records
# and both near-miss); drop the earlier same-stage record; print an empty
# stage; print the whole 100 KB line in a near-miss row.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S245" || test_done

CR=$'\r'
LF=$'\n'
rec() { rh_rec "$1" "$2" "${3-}"; }
A="$(rec Discovery m-a)"
B="$(rec Planning m-b)"
C="$(rec Test m-c)"
D="$(rec Implementation m-d)"

# last_ok <stage>: sets LAST_TXT to the line of the last ok row of that stage
# (bundle-wide: the highest index, then the last in that body); returns 1 if none.
last_ok() {
  local want="$1" i=0
  LAST_TXT=""
  LAST_IDX=""
  while [ "$i" -lt "$RH_N" ]; do
    if [ "${RH_CLS[$i]}" = ok ] && [ "${RH_STG[$i]}" = "$want" ]; then
      LAST_TXT="${RH_TXT[$i]}"
      LAST_IDX="${RH_IDX[$i]}"
    fi
    i=$((i + 1))
  done
  [ -n "$LAST_TXT" ]
}

# --- R4: fence state does not leak between bodies --------------------------------
b1="${A}"
b2="\`\`\`${LF}${B}"                      # an unclosed fence in body 2
b3="${C}"                                  # must be ok: the fence ended with body 2
b4="\`\`\`${LF}x${LF}\`\`\`${LF}${D}"      # a closed fence, then a live record
b5="~~~${LF}${A}"                          # another unclosed fence, last body
bundle="$(rh_join_bundle "$b1" "$b2" "$b3" "$b4" "$b5")"
for mode in $RH_MODES; do
  rh_bundle "S245/fence reset" "$mode" model-record "$bundle" || continue
  want_per_body=("ok" "quoted" "ok" "ok" "quoted")
  i=0
  while [ "$i" -lt 5 ]; do
    got="$(rh_classes_for $((i + 1)))"
    [ "$got" = "${want_per_body[$i]}" ] || fail "S245/fence reset [$mode] — body $((i + 1)): want '${want_per_body[$i]}', got '$got' (fence state must not cross a body)"
    i=$((i + 1))
  done
  [ "$(rh_text_for 3 ok)" = "$C" ] || fail "S245/fence reset [$mode] — body 3 (after the unclosed fence of body 2) is not read verbatim"
  [ "$(rh_stage_for 4 ok)" = "Implementation" ] || fail "S245/fence reset [$mode] — body 4's ok row has stage '$(rh_stage_for 4 ok)'"
done

# --- bodies in order, indices kept across empty bodies ---------------------------
bundle="$(rh_join_bundle "" "$A" "" "" "$B" "no record here" "$C")"
for mode in $RH_MODES; do
  rh_bundle "S245/indices" "$mode" model-record "$bundle" || continue
  [ "$(rh_classes)" = "ok ok ok" ] || fail "S245/indices [$mode] — want 'ok ok ok', got '$(rh_classes)'"
  [ "${RH_IDX[0]-}" = 2 ] && [ "${RH_IDX[1]-}" = 5 ] && [ "${RH_IDX[2]-}" = 7 ] \
    || fail "S245/indices [$mode] — an empty or record-less body keeps its number: want indices 2 5 7, got '${RH_IDX[*]-}'"
done
for mode in $RH_MODES; do
  rh_run "$mode" rec_scan_bundle model-record ""
  [ "$RH_RC" -eq 0 ] && [ -z "$RH_OUT" ] || fail "S245/empty bundle [$mode] — an empty bundle gives status 0 and no rows, got rc=$RH_RC out='$RH_OUT'"
  rh_run "$mode" rec_scan_bundle model-record "${RH_SEP}${RH_SEP}${RH_SEP}"
  [ "$RH_RC" -eq 0 ] && [ -z "$RH_OUT" ] || fail "S245/empty bodies [$mode] — three empty bodies give status 0 and no rows, got rc=$RH_RC out='$RH_OUT'"
done

# --- rec_scan of body i equals the bundle rows of body i (index 1) -------------------
bodies=("$A" "${B}${LF}> ${C}${LF}  ${D}" "\`\`\`${LF}${A}" "x${LF}${LF}${C}${LF}${D}" "${B}${LF}${B}")
bundle="$(rh_join_bundle "${bodies[@]}")"
for mode in $RH_MODES; do
  rh_bundle "S245/equivalence" "$mode" model-record "$bundle" || continue
  bundle_out="$RH_OUT"
  i=0
  while [ "$i" -lt "${#bodies[@]}" ]; do
    idx=$((i + 1))
    expect="$(printf '%s\n' "$bundle_out" | LC_ALL=C awk -F'\t' -v n="$idx" '$1 == n { sub(/^[0-9]+\t/, "1\t"); print }')"
    rh_run "$mode" rec_scan model-record "${bodies[$i]}"
    [ "$RH_RC" -eq 0 ] || fail "S245/equivalence [$mode] — rec_scan of body $idx exited $RH_RC"
    [ "$RH_OUT" = "$expect" ] || fail "S245/equivalence [$mode] — rec_scan of body $idx differs from its bundle rows:${LF}rec_scan: $RH_OUT${LF}bundle:   $expect"
    i=$((i + 1))
  done
done

# --- two records of one stage in one body: both are rows, the later one is last ---
old="$(rec Test m-old)"
new="$(rec Test m-new 'effort="x"')"
for mode in $RH_MODES; do
  rh_scan "S245/same stage" "$mode" model-record "${old}${LF}some prose${LF}${new}" || continue
  [ "$(rh_classes)" = "ok ok" ] || fail "S245/same stage [$mode] — both ok rows are printed in body order, got '$(rh_classes)'"
  if last_ok Test; then
    [ "$LAST_TXT" = "$new" ] || fail "S245/same stage [$mode] — the last ok Test row is '$LAST_TXT', want the later record"
    rh_expect_field "S245/same stage" "$mode" "$LAST_TXT" model m-new
    rh_expect_field "S245/same stage" "$mode" "$LAST_TXT" effort x
  else
    fail "S245/same stage [$mode] — no ok Test row"
  fi
done
# the same across a bundle: the later body's record is the later one
bundle="$(rh_join_bundle "$old" "$new")"
for mode in $RH_MODES; do
  rh_bundle "S245/same stage bundle" "$mode" model-record "$bundle" || continue
  last_ok Test && [ "$LAST_IDX" = 2 ] && [ "$LAST_TXT" = "$new" ] || fail "S245/same stage bundle [$mode] — the last ok Test row must be body 2's, got index '$LAST_IDX' line '$LAST_TXT'"
done

# --- CRLF and a lone CR are line endings (A31a), never part of a line ----------------
for mode in $RH_MODES; do
  rh_scan "S245/CRLF" "$mode" model-record "${A}${CR}${LF}${B}${CR}${LF}" || continue
  [ "$(rh_classes)" = "ok ok" ] && [ "${RH_TXT[0]-}" = "$A" ] && [ "${RH_TXT[1]-}" = "$B" ] \
    || fail "S245/CRLF [$mode] — a CRLF body reads as the LF body: want 'ok ok' with the lines verbatim (no CR), got '$(rh_classes)' '${RH_TXT[0]-}' '${RH_TXT[1]-}'"
  rh_scan "S245/lone CR" "$mode" model-record "${A}${CR}${B}${CR}${C}" || continue
  [ "$(rh_classes)" = "ok ok ok" ] && [ "${RH_TXT[0]-}" = "$A" ] && [ "${RH_TXT[1]-}" = "$B" ] && [ "${RH_TXT[2]-}" = "$C" ] \
    || fail "S245/lone CR [$mode] — a lone CR is a line break: three records, want 'ok ok ok', got '$(rh_classes)'"
  rh_scan "S245/CR then LF then CR" "$mode" model-record "${A}${CR}${LF}${CR}${LF}${B}" || continue
  [ "$(rh_classes)" = "ok ok" ] || fail "S245/CR,LF,CR,LF [$mode] — want 'ok ok', got '$(rh_classes)'"
  # a record inside a fence stays quoted when the fence lines end in CRLF
  rh_scan "S245/CRLF fence" "$mode" model-record "\`\`\`${CR}${LF}${A}${CR}${LF}\`\`\`${CR}${LF}${B}" || continue
  [ "$(rh_classes)" = "quoted ok" ] || fail "S245/CRLF fence [$mode] — want 'quoted ok', got '$(rh_classes)'"
done
bundle="$(rh_join_bundle "${A}${CR}${LF}${B}" "${C}${CR}${D}")"
for mode in $RH_MODES; do
  rh_bundle "S245/CR in a bundle" "$mode" model-record "$bundle" || continue
  [ "$(rh_classes_for 1)" = "ok ok" ] && [ "$(rh_classes_for 2)" = "ok ok" ] || fail "S245/CR in a bundle [$mode] — want 'ok ok' in both bodies, got '$(rh_classes_for 1)' and '$(rh_classes_for 2)'"
done

# --- an override whose reason holds `>` is a near-miss, never a waiver ------------
po_bad='<!-- pipeline-override: decided-by="human" scope="single-session" reason="a > b" -->'
po_ok='<!-- pipeline-override: decided-by="human" scope="skip=Test" reason="no behaviour changes" -->'
for mode in $RH_MODES; do
  rh_scan "S245/override >" "$mode" pipeline-override "${po_bad}${LF}${po_ok}" || continue
  [ "$(rh_classes)" = "near-miss ok" ] || fail "S245/override > [$mode] — want 'near-miss ok', got '$(rh_classes)'"
  [ "${RH_STG[0]-}" = "?" ] && [ "${RH_STG[1]-}" = "?" ] || fail "S245/override > [$mode] — an override row's stage field is '?', got '${RH_STG[0]-}' '${RH_STG[1]-}'"
  rh_expect_field "S245/override" "$mode" "${RH_TXT[1]-}" scope "skip=Test"
done

# --- no field is ever empty; a near-miss with no readable stage says '?' --------------
nostage="<!-- model-record: model=\"m1\" -->"
tabbed="$(printf '<!-- model-record: stage=Test model="m1" floor-basis="a\tb" -->')"
bigline="<!-- model-record: stage=Review model=\"m1\" floor-basis=\"$(printf 'y%.0s' $(seq 1 3000))>\" -->"
body="${nostage}${LF}${tabbed}${LF}${bigline}${LF}\`${A}\`${LF}${A}"
for mode in $RH_MODES; do
  rh_scan "S245/shape" "$mode" model-record "$body" || continue
  [ "$(rh_classes)" = "near-miss near-miss near-miss quoted ok" ] || fail "S245/shape [$mode] — want 'near-miss near-miss near-miss quoted ok', got '$(rh_classes)'"
  [ "${RH_STG[0]-}" = "?" ] || fail "S245/shape [$mode] — a line with no stage= has stage '?', got '${RH_STG[0]-}'"
  i=0
  while [ "$i" -lt "$RH_N" ]; do
    if [ "${RH_CLS[$i]}" != ok ] && [ "${#RH_TXT[$i]}" -gt 400 ]; then
      fail "S245/shape [$mode] — row $((i + 1)): a near-miss or quoted row holds a reason of ${#RH_TXT[$i]} bytes; a long line is cut (A32: the first 200 bytes), never dumped whole"
    fi
    i=$((i + 1))
  done
done

test_done
