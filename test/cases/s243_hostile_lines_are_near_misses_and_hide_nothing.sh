#!/usr/bin/env bash
# S243 — each #405 defect class is a near-miss and never hides a later (or earlier) record; the same through a bundle (R2)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC2; A31 (near-miss), A31a (classes, a record
# is one whole line), A32a (bundles). Seam: rec_scan (one body) and
# rec_scan_bundle (bodies joined by U+001E), the rows they print, rec_field on
# the ok line they return. For each hostile line (the #405 rounds 1 to 4 and
# #402) one valid record sits after it, before it, and on both sides, in ONE
# body; the hostile line is a near-miss, every valid record is ok with its
# exact line and fields, and the row count is exactly the candidate count, so
# a hostile line never consumes the next line and never produces a second row.
#
# Threat model: ACCIDENTAL defects that took the old parser down in #397 and
# #405: a `>` or `<` in a value, an odd or open quote, `-->` or `<!--` inside a
# value, an invalid or multibyte character right after `stage=`, a split
# record, a quoted stage, an unquoted model, an inline record. Also the
# deliberate shapes a careless author can produce by typing a marker. It does
# NOT claim a forger cannot write a strict line: a typed strict line is
# byte-identical to emitter output and no artifact can show otherwise (stated
# limit, A34a).
#
# Locales: C, UTF8 and LANG (LC_ALL UNSET, LANG a UTF-8 locale; the AC2
# environment). The bytes after `stage=` are 0xFF and a truncated `\342\200`:
# BWK awk aborts on those under a UTF-8 locale unless every external command
# carries its own `LC_ALL=C` (a `local LC_ALL=C` does not reach a child in
# bash 3.2 when the caller did not export it; QA critique D1).
#
# U+001E is the bundle separator, so a body that holds one is not a bundle
# case: callers remove it from each body first (A32a), which makes the line
# whole again. The U+001E-in-a-value case therefore runs through rec_scan only,
# where the byte is a control byte and the line is a near-miss.
#
# Red today: stubs (return 99). Mutations this case must not survive (kill
# table): allow `>` or `<` in a value; make the reader multi-line (a split
# record reads as ok, or an open quote runs on); let the near-miss branch
# consume the following line; classify an inline record ok; read an unquoted
# model or a quoted stage as ok; a reader that aborts on a multibyte byte (no
# per-command LC_ALL=C) and returns no rows for the whole body.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S243" || test_done

REC='<!-- model-record: '
valid_a="${REC}stage=Planning model=\"sentinel-a\" -->"
valid_b="${REC}stage=Test model=\"sentinel-b\" floor-basis=\"not a Review, ignored\" -->"

# The cases: label, hostile text (may hold a newline), the stage field the
# near-miss row must carry ("" = only "not empty"). A bare, valid stage= token
# on the line is the row's stage (A32); anything else is '?' or the token and
# is only required to be non-empty.
CASE_LABELS=()
CASE_TEXT=()
CASE_STAGE=()
add_case() { CASE_LABELS+=("$1"); CASE_TEXT+=("$2"); CASE_STAGE+=("$3"); }

add_case "> in a value (#397 round 1)" "${REC}stage=Review model=\"m1\" floor-basis=\"stronger > weaker\" -->" Review
add_case "< in a value" "${REC}stage=Review model=\"m1\" floor-basis=\"a < b\" -->" Review
add_case "an odd quote (#405 round 2)" "${REC}stage=Review model=\"m1\" floor-basis=\"a\"b\" -->" Review
add_case "an open quote that never closes (round 3)" "${REC}stage=Review model=\"m1\" floor-basis=\"never closed -->" Review
add_case "--> inside a value" "${REC}stage=Review model=\"m1\" floor-basis=\"x --> y\" -->" Review
add_case "<!-- inside a value" "${REC}stage=Review model=\"m1\" floor-basis=\"x <!-- y\" -->" Review
add_case "a whole record nested in a value" "${REC}stage=Review model=\"m1\" floor-basis=\"see ${REC}stage=Test model=m2 -->\" -->" Review
add_case "invalid UTF-8 right after stage= (round 2, BWK abort)" "$(printf '%sstage=\377Test model="m1" -->' "$REC")" ""
add_case "a truncated UTF-8 sequence right after stage=" "$(printf '%sstage=\342\200Test model="m1" -->' "$REC")" ""
add_case "a multibyte character right after stage=" "$(printf '%sstage=\303\251Test model="m1" -->' "$REC")" ""
add_case "an invalid byte inside a value, then a stray quote" "$(printf '%sstage=Review model="m1" floor-basis="a\377b"c" -->' "$REC")" Review
add_case "a quoted stage (#402)" "${REC}stage=\"Planning\" model=\"m1\" -->" ""
add_case "an unquoted model (#402)" "${REC}stage=Planning model=m1 -->" Planning
add_case "an empty model" "${REC}stage=Planning model=\"\" -->" Planning
add_case "a blank model" "${REC}stage=Planning model=\"   \" -->" Planning
add_case "no model at all" "${REC}stage=Planning -->" Planning
add_case "a record split over two lines" "${REC}stage=Test${RH_LF}model=\"m1\" -->" Test
add_case "an inline record after prose" "Done. ${REC}stage=Test model=\"m1\" -->" Test
add_case "text after the closing arrow" "${REC}stage=Test model=\"m1\" --> and more" Test
add_case "no closing arrow" "${REC}stage=Test model=\"m1\"" Test
add_case "two records on one line" "${REC}stage=Test model=\"m1\" --> ${REC}stage=Review model=\"m2\" floor-basis=\"f\" -->" Test
add_case "a tab inside a value" "$(printf '%sstage=Review model="m1" floor-basis="a\tb" -->' "$REC")" Review
add_case "a C0 control byte inside a value" "$(printf '%sstage=Review model="m1" floor-basis="a\001b" -->' "$REC")" Review
add_case "DEL inside a value" "$(printf '%sstage=Review model="m1" floor-basis="a\177b" -->' "$REC")" Review
add_case "a lone CR inside a value splits the line" "$(printf '%sstage=Review model="m1" floor-basis="a\rb" -->' "$REC")" Review
add_case "CRLF inside a value splits the line" "$(printf '%sstage=Review model="m1" floor-basis="a\r\nb" -->' "$REC")" Review
add_case "a newline inside a value" "${REC}stage=Review model=\"m1\" floor-basis=\"a${RH_LF}b\" -->" Review
add_case "an upper-case attribute name" "${REC}stage=Test model=\"m1\" Effort=\"x\" -->" Test
add_case "a bare word where an attribute belongs" "${REC}stage=Test model=\"m1\" extra -->" Test
add_case "NBSP after the colon" "$(printf '<!-- model-record:\302\240stage=Test model="m1" -->')" ""

# --- one body per case, rec_scan: hostile after / before / on both sides ----
n_cases="${#CASE_LABELS[@]}"
for mode in $RH_MODES; do
  i=0
  while [ "$i" -lt "$n_cases" ]; do
    label="${CASE_LABELS[$i]}"
    hostile="${CASE_TEXT[$i]}"
    want_stage="${CASE_STAGE[$i]}"
    for variant in after before both; do
      case "$variant" in
        after) body="${hostile}${RH_LF}${valid_a}"; want="near-miss ok"; hpos=0; vpos=1 ;;
        before) body="${valid_a}${RH_LF}${hostile}"; want="ok near-miss"; hpos=1; vpos=0 ;;
        both) body="${valid_a}${RH_LF}${hostile}${RH_LF}${valid_b}"; want="ok near-miss ok"; hpos=1; vpos=0 ;;
      esac
      rh_scan "S243/$label ($variant)" "$mode" model-record "$body" || continue
      if [ "$(rh_classes)" != "$want" ]; then
        fail "S243/$label ($variant) [$mode] — want classes '$want', got '$(rh_classes)' (a hostile line must be one near-miss and hide no record)"
        continue
      fi
      [ "${RH_TXT[$vpos]}" = "$valid_a" ] || fail "S243/$label ($variant) [$mode] — the valid record is not returned verbatim: '${RH_TXT[$vpos]}'"
      [ "${RH_STG[$vpos]}" = "Planning" ] || fail "S243/$label ($variant) [$mode] — the valid record's stage is '${RH_STG[$vpos]}', want Planning"
      if [ "$variant" = both ]; then
        [ "${RH_TXT[2]}" = "$valid_b" ] && [ "${RH_STG[2]}" = "Test" ] || fail "S243/$label ($variant) [$mode] — the second valid record is not read as ok Test verbatim: '${RH_STG[2]}' '${RH_TXT[2]}'"
      fi
      if [ -n "$want_stage" ] && [ "${RH_STG[$hpos]}" != "$want_stage" ]; then
        fail "S243/$label ($variant) [$mode] — the near-miss row's stage is '${RH_STG[$hpos]}', want '$want_stage' (the bare stage= token)"
      fi
      rh_expect_field "S243/$label ($variant)" "$mode" "${RH_TXT[$vpos]}" model sentinel-a
    done
    i=$((i + 1))
  done
done

# --- the same cases as ONE bundle (A32a: one awk pass, fence state per body) -
# Body index i+1 is case i, 'after' variant. The bundle must give the same
# classes as the per-body calls, row for row, with the right body index.
bundle_args=()
i=0
while [ "$i" -lt "$n_cases" ]; do
  bundle_args+=("${CASE_TEXT[$i]}${RH_LF}${valid_a}")
  i=$((i + 1))
done
bundle="$(rh_join_bundle "${bundle_args[@]}")"
for mode in $RH_MODES; do
  rh_bundle "S243/bundle" "$mode" model-record "$bundle" || continue
  i=0
  while [ "$i" -lt "$n_cases" ]; do
    idx=$((i + 1))
    got="$(rh_classes_for "$idx")"
    [ "$got" = "near-miss ok" ] || fail "S243/bundle/${CASE_LABELS[$i]} [$mode] — body $idx: want 'near-miss ok', got '$got'"
    [ "$(rh_text_for "$idx" ok 1)" = "$valid_a" ] || fail "S243/bundle/${CASE_LABELS[$i]} [$mode] — body $idx: the valid record is not returned verbatim"
    i=$((i + 1))
  done
  [ "$RH_N" -eq $((2 * n_cases)) ] || fail "S243/bundle [$mode] — want exactly $((2 * n_cases)) rows (one near-miss and one ok per body), got $RH_N"
done

# --- round 3: an open quote at the end of one comment, a record in the next --
# (the bundle form of #397 round 3: a quote opened in body 1 never reaches
# body 2, whatever body 2 holds)
b1="${REC}stage=Review model=\"m1\" floor-basis=\"opens and never closes"
b2="${REC}stage=Test model=\"m2\" -->"
b3="${REC}stage=Implementation model=\"m3\" -->"
for mode in $RH_MODES; do
  rh_bundle "S243/round 3" "$mode" model-record "$(rh_join_bundle "$b1" "$b2" "$b3")" || continue
  [ "$(rh_classes_for 1)" = "near-miss" ] || fail "S243/round 3 [$mode] — body 1 (the open quote) must be one near-miss, got '$(rh_classes_for 1)'"
  [ "$(rh_classes_for 2)" = "ok" ] && [ "$(rh_text_for 2 ok)" = "$b2" ] || fail "S243/round 3 [$mode] — body 2 must be its own ok record, got '$(rh_classes_for 2)'"
  [ "$(rh_classes_for 3)" = "ok" ] && [ "$(rh_text_for 3 ok)" = "$b3" ] || fail "S243/round 3 [$mode] — body 3 must be its own ok record, got '$(rh_classes_for 3)'"
done

# --- U+001E inside a body: the byte is a control byte in a value --------------
sep_line="${REC}stage=Review model=\"m1\" floor-basis=\"a${RH_SEP}b\" -->"
for mode in $RH_MODES; do
  rh_scan "S243/U+001E" "$mode" model-record "${sep_line}${RH_LF}${valid_a}" || continue
  [ "$(rh_classes)" = "near-miss ok" ] || fail "S243/U+001E [$mode] — a U+001E inside a value is a control byte: want 'near-miss ok', got '$(rh_classes)'"
done

# --- the hostile line is never consumed by, and never consumes, its neighbour -
# (a hostile line between two valid ones, repeated: the row count is the
# candidate count, so the reader is line-local)
body=""
i=0
while [ "$i" -lt 6 ]; do
  body="${body}${valid_a}${RH_LF}${CASE_TEXT[0]}${RH_LF}"
  i=$((i + 1))
done
for mode in $RH_MODES; do
  rh_scan "S243/alternating" "$mode" model-record "$body" || continue
  [ "$(rh_classes)" = "ok near-miss ok near-miss ok near-miss ok near-miss ok near-miss ok near-miss" ] \
    || fail "S243/alternating [$mode] — six ok/near-miss pairs expected, got '$(rh_classes)'"
done

test_done
