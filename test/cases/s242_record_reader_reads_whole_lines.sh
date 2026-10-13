#!/usr/bin/env bash
# S242 — rec_scan reads a well-formed whole line as one ok row with its exact fields, under three locale environments (R1)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC1 (the shapes), AC6 (the row shape); A31 and
# A31a (the grammar), A32a (rows, locales). Seam: the sourced lib's rec_scan,
# rec_field and the row they print: <body-index> TAB <class> TAB <stage> TAB
# <line>. Nothing here looks at how the reader parses (tdd-seams): the cases
# build a line from named parts, so every expected value is known by
# construction and is never taken from the reader.
#
# Threat model: ACCIDENTAL defects only. A regex typo, a bash-3.2 `[[ =~ ]]`
# quirk, a locale that leaks into grep or awk (the #405 round-2 class: with
# LC_ALL unset and LANG a UTF-8 locale, BWK awk aborts on an invalid byte), a
# value byte class left out. A role that pastes a valid line is not an
# attacker here; the deliberate-injection shapes are S243 and S249.
#
# Every case runs under C (LC_ALL=C), UTF8 (both set) and LANG (LC_ALL UNSET,
# LANG a UTF-8 locale: how production runs a sourced lib). A UTF-8 locale that
# is not installed fails on a macOS host and is skipped, loudly, elsewhere.
#
# Red today: the three functions are stubs that return 99 (the red commit),
# so each case fails on an assertion about rec_scan's exit status or rows.
# None of S242 is a regression scenario (the old parser has no rec_scan).
# Mutations this case must not survive (QA kill table): forbid bytes 0x80 to
# 0xFF in a value; drop the trailing-blank allowance before or after `-->`;
# allow indentation (that is S244's); read a record with a blank model;
# `stage=` accepted from a different alternation (a sixth stage); a value cut at
# `--`, `=`, a backtick or `$`.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S242" || test_done

# check_ok <label> <line> <stage> <model> [name value]...
# The line, alone and inside a body with prose around it, gives exactly one ok
# row: index 1, the stage, the line itself; rec_field reads model and every
# named attribute exactly, and prints nothing for an attribute that is absent.
check_ok() {
  local label="$1" line="$2" stage="$3" model="$4" mode body name value i
  shift 4
  local args=("$@")
  body="An intro line.${RH_LF}${RH_LF}$line${RH_LF}${RH_LF}A closing line."
  for mode in $RH_MODES; do
    rh_scan "S242/$label alone" "$mode" model-record "$line" || continue
    if [ "$RH_N" -ne 1 ] || [ "$(rh_classes)" != "ok" ]; then
      fail "S242/$label alone [$mode] — want exactly one ok row, got $RH_N: '$(rh_classes)'"
      continue
    fi
    [ "${RH_IDX[0]}" = "1" ] || fail "S242/$label [$mode] — a single body is body 1, got index '${RH_IDX[0]}'"
    [ "${RH_STG[0]}" = "$stage" ] || fail "S242/$label [$mode] — stage field '${RH_STG[0]}', want '$stage'"
    [ "${RH_TXT[0]}" = "$line" ] || fail "S242/$label [$mode] — line field '${RH_TXT[0]}' is not the line '$line'"
    rh_expect_field "S242/$label" "$mode" "$line" model "$model"
    i=0
    while [ "$i" -lt "${#args[@]}" ]; do
      name="${args[$i]}"
      value="${args[$((i + 1))]}"
      rh_expect_field "S242/$label" "$mode" "$line" "$name" "$value"
      i=$((i + 2))
    done
    rh_expect_field "S242/$label (absent attribute)" "$mode" "$line" no-such-attribute ""
    # the same line inside a body of prose: still exactly one row
    rh_scan "S242/$label in prose" "$mode" model-record "$body" || continue
    if [ "$(rh_classes)" != "ok" ] || [ "${RH_TXT[0]}" != "$line" ]; then
      fail "S242/$label in prose [$mode] — want one ok row holding the line, got '$(rh_classes)' / '${RH_TXT[0]-}'"
    fi
  done
}

M='claude-opus-5-5'

# --- the stage x floor-basis matrix (every stage, with and without) ----------
for st in Discovery Planning Test Implementation Review; do
  check_ok "$st without floor-basis" "<!-- model-record: stage=$st model=\"$M\" -->" "$st" "$M"
  check_ok "$st with floor-basis" "<!-- model-record: stage=$st model=\"$M\" floor-basis=\"same model, stronger judgment\" -->" "$st" "$M" floor-basis "same model, stronger judgment"
done

# --- legacy shapes: spaces in the model, effort and same-model-exception -----
# (read and ignored: a legacy effort attribute is tolerated and never read as
# anything but an attribute, #424)
check_ok "model with spaces" '<!-- model-record: stage=Implementation model="Claude Sonnet 5" -->' Implementation "Claude Sonnet 5"
check_ok "legacy effort unknown" '<!-- model-record: stage=Planning model="claude-opus-5-5" effort="unknown" -->' Planning "claude-opus-5-5" effort unknown
check_ok "legacy effort session-default" '<!-- model-record: stage=Planning model="claude-opus-5-5" effort="session-default" -->' Planning "claude-opus-5-5" effort session-default
check_ok "legacy effort and same-model-exception" '<!-- model-record: stage=Review model="claude-sonnet-5" effort="high" same-model-exception="no cheaper model clears the floor" floor-basis="stronger on this diff" -->' Review claude-sonnet-5 effort high same-model-exception "no cheaper model clears the floor" floor-basis "stronger on this diff"
check_ok "attributes in the other order" '<!-- model-record: stage=Review model="m1" same-model-exception="x" effort="low" floor-basis="f" -->' Review m1 floor-basis f effort low same-model-exception x

# --- separators and trailing blanks ------------------------------------------
check_ok "trailing blanks and a tab" "$(printf '<!-- model-record: stage=Test model="m1" -->  \t ')" Test m1
check_ok "tabs as separators" "$(printf '<!--\tmodel-record:\tstage=Test\tmodel="m1"\tfloor-basis="x"\t-->')" Test m1 floor-basis x
check_ok "no blank after the opener, none before the closer" '<!--model-record:stage=Test model="m1"-->' Test m1
check_ok "many blanks" '<!--     model-record:     stage=Test     model="m1"     effort="e"     -->' Test m1 effort e

# --- value bytes: everything but quote, <, >, a control byte -----------------
check_ok "valid UTF-8" "$(printf '<!-- model-record: stage=Review model="m1" floor-basis="a \342\200\224 b \342\234\223 \303\251 \360\237\230\200" -->')" Review m1 floor-basis "$(printf 'a \342\200\224 b \342\234\223 \303\251 \360\237\230\200')"
check_ok "NEL LS PS in a value (the emitter refuses them, the reader reads them)" "$(printf '<!-- model-record: stage=Review model="m1" floor-basis="a\302\205b\342\200\250c\342\200\251d" -->')" Review m1 floor-basis "$(printf 'a\302\205b\342\200\250c\342\200\251d')"
check_ok "invalid UTF-8 byte 0xFF" "$(printf '<!-- model-record: stage=Review model="m1" floor-basis="a\377b" -->')" Review m1 floor-basis "$(printf 'a\377b')"
check_ok "truncated UTF-8 sequence" "$(printf '<!-- model-record: stage=Review model="m1" floor-basis="a\342\200b" -->')" Review m1 floor-basis "$(printf 'a\342\200b')"
check_ok "lone continuation byte and overlong form" "$(printf '<!-- model-record: stage=Review model="m1" floor-basis="a\200b\300\257c" -->')" Review m1 floor-basis "$(printf 'a\200b\300\257c')"
check_ok "invalid byte in the model (legacy)" "$(printf '<!-- model-record: stage=Planning model="m\377x" -->')" Planning "$(printf 'm\377x')"
check_ok "shell and printf metacharacters" "<!-- model-record: stage=Review model=\"m1\" floor-basis=\"a -- b = c 'q' \$x \$(y) * ? [ ] % \\ \`t\` ; | & ~ # ! { }\" -->" Review m1 floor-basis "a -- b = c 'q' \$x \$(y) * ? [ ] % \\ \`t\` ; | & ~ # ! { }"
check_ok "value ending in ' model='" '<!-- model-record: stage=Review model="m1" floor-basis="beats model=" -->' Review m1 floor-basis "beats model="
check_ok "value ending in ' stage='" '<!-- model-record: stage=Review model="m1" floor-basis="was stage=" -->' Review m1 floor-basis "was stage="
check_ok "empty floor-basis is well-formed" '<!-- model-record: stage=Review model="m1" floor-basis="" -->' Review m1 floor-basis ""
check_ok "a leading dash and a lone dash" '<!-- model-record: stage=Review model="-m1" floor-basis="-" -->' Review "-m1" floor-basis "-"
long="$(printf 'x%.0s' $(seq 1 600))"
check_ok "a long value is the reader's business (the emitter's 500-byte limit is its own)" "<!-- model-record: stage=Review model=\"m1\" floor-basis=\"$long\" -->" Review m1 floor-basis "$long"

# --- the second kind: pipeline-override (A31: same whole-line and value rules)
po='<!-- pipeline-override: decided-by="human" scope="single-session" reason="a documentation-only change" -->'
for mode in $RH_MODES; do
  if rh_scan "S242/override" "$mode" pipeline-override "$po"; then
    [ "$(rh_classes)" = "ok" ] || fail "S242/override [$mode] — want one ok row, got '$(rh_classes)'"
    [ "${RH_N}" -eq 1 ] && [ "${RH_STG[0]}" = "?" ] || fail "S242/override [$mode] — an override has no stage: the stage field is '?', got '${RH_STG[0]-}'"
    [ "${RH_TXT[0]-}" = "$po" ] || fail "S242/override [$mode] — line field is not the line: '${RH_TXT[0]-}'"
    rh_expect_field "S242/override" "$mode" "$po" decided-by human
    rh_expect_field "S242/override" "$mode" "$po" scope single-session
    rh_expect_field "S242/override" "$mode" "$po" reason "a documentation-only change"
  fi
  # the two kinds do not read each other's lines
  if rh_scan "S242/kinds" "$mode" model-record "$po"; then
    [ "$RH_N" -eq 0 ] || fail "S242/kinds [$mode] — rec_scan model-record must read no row from an override line, got: $(rh_classes)"
  fi
  if rh_scan "S242/kinds" "$mode" pipeline-override "$(rh_rec Test m1)"; then
    [ "$RH_N" -eq 0 ] || fail "S242/kinds [$mode] — rec_scan pipeline-override must read no row from a model-record line, got: $(rh_classes)"
  fi
done

# --- nothing to read: no rows, a zero status (a body without a record is not a failure)
for mode in $RH_MODES; do
  rh_run "$mode" rec_scan model-record "just prose, and the word model-record: here, with no opener"
  [ "$RH_RC" -eq 0 ] && [ -z "$RH_OUT" ] || fail "S242/no record [$mode] — a body without a candidate gives status 0 and no rows, got rc=$RH_RC out='$RH_OUT' err='$RH_ERR'"
  rh_run "$mode" rec_scan model-record ""
  [ "$RH_RC" -eq 0 ] && [ -z "$RH_OUT" ] || fail "S242/empty body [$mode] — an empty body gives status 0 and no rows, got rc=$RH_RC out='$RH_OUT'"
done

test_done
