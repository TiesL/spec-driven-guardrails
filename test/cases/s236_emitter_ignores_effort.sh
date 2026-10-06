#!/usr/bin/env bash
# S236 — model-record-emit.sh no longer writes effort, and still accepts
# `--effort <anything>` for one release, ignoring it with one stderr line.
# Covers: F39, F40
#
# Issue #424 (V3 of the #411 redesign; A33 as amended by A33a), AC1. A stale
# prompt in an adopted project still passes `--effort high`: the wrapper prints
# `<!-- model-record: stage=<S> model="<M>"[ floor-basis="<F>"] -->` (no effort
# attribute), exits 0, and prints on stderr EXACTLY `effort is no longer
# recorded (#413); drop --effort from your prompt` (one line; no other text).
# A call without --effort prints nothing on stderr. A refusal for any other
# reason (bad stage, bad model, missing floor-basis) is unchanged: exit 2,
# empty stdout. The flag is removed in the next release (a PRD debt row records
# that step: S238). Seam: the wrapper's stdout, stderr and exit status, run
# under LC_ALL=C and a UTF-8 locale, plus the gate as the end-to-end reader of
# an emitted line next to a legacy-effort one.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

emit="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-emit.sh"
if [ ! -x "$emit" ]; then
  fail "S236 — skills/pre-merge-review/model-record-emit.sh is missing or not executable"
  test_done
fi
command -v jq >/dev/null 2>&1 || { fail "S236 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
: "$rf_status"

avail="$(locale -a 2>/dev/null)"
utf8=""
for cand in en_US.UTF-8 nl_NL.UTF-8 C.UTF-8 en_US.utf8 C.utf8; do
  if grep -qix "$cand" <<<"$avail"; then utf8="$cand"; break; fi
done
locales="C"
[ -z "$utf8" ] || locales="C $utf8"

# run <locale> <emit path> args...: sets out, err, rc
run() {
  local loc="$1" path="$2"
  shift 2
  out="$(LC_ALL="$loc" LANG="$loc" "$path" "$@" 2>"$SANDBOX/err")"
  rc=$?
  err="$(cat "$SANDBOX/err")"
}

# A stale prompt in an adopted project still passes --effort. The wrapper
# prints the effort-free line on stdout, exits 0, and prints on stderr
# exactly one line (A33a). Any value is accepted: the flag is ignored.
warn='effort is no longer recorded (#413); drop --effort from your prompt'
for loc in $locales; do
  for ef in high low medium unknown Low max session-default 1 ''; do
    run "$loc" "$emit" --stage Implementation --model m --effort "$ef"
    [ "$rc" -eq 0 ] || { fail "S236 AC1 effort '$ef' [$loc] — expected exit 0 (the flag is ignored), got $rc: $err"; continue; }
    [ "$out" = '<!-- model-record: stage=Implementation model="m" -->' ] \
      || fail "S236 AC1 effort '$ef' [$loc] — stdout must be exactly the effort-free line, got: '$out'"
    [ "$err" = "$warn" ] \
      || fail "S236 AC1 effort '$ef' [$loc] — stderr must be exactly '$warn', got: '$err'"
  done
  # the flag position does not matter; a Review line keeps its floor-basis
  run "$loc" "$emit" --effort high --stage Review --floor-basis 'stronger model' --model m
  [ "$rc" -eq 0 ] && [ "$out" = '<!-- model-record: stage=Review model="m" floor-basis="stronger model" -->' ] \
    || fail "S236 AC1 Review with a leading --effort [$loc] — rc=$rc out='$out' err='$err'"
  [ "$err" = "$warn" ] || fail "S236 AC1 Review with a leading --effort [$loc] — stderr must be exactly the one warning line, got: '$err'"
  [ "$(printf '%s\n' "$err" | grep -c .)" -eq 1 ] || fail "S236 AC1 [$loc] — the warning is one line"
  # --effort in EVERY slot, after --floor-basis included (review round 1,
  # pr447-s236-effort-after-floor-basis-unpinned): it must not reset, consume
  # or reorder any other flag. Six orders of the three flags x four slots.
  fbline='<!-- model-record: stage=Review model="m" floor-basis="stronger model" -->'
  for order in "S M F" "S F M" "M S F" "M F S" "F S M" "F M S"; do
    for slot in 0 1 2 3; do
      set --
      n=0
      [ "$slot" -ne 0 ] || set -- --effort high
      for k in $order; do
        case "$k" in
          S) set -- "$@" --stage Review ;;
          M) set -- "$@" --model m ;;
          F) set -- "$@" --floor-basis 'stronger model' ;;
        esac
        n=$((n + 1))
        [ "$n" -ne "$slot" ] || set -- "$@" --effort high
      done
      run "$loc" "$emit" "$@"
      [ "$rc" -eq 0 ] && [ "$out" = "$fbline" ] && [ "$err" = "$warn" ] \
        || fail "S236 AC1 --effort in slot $slot of order '$order' [$loc] — expected the Review line with its floor-basis, exit 0 and the one warning; rc=$rc out='$out' err='$err'"
    done
  done
  # --effort after --floor-basis must not forgive a floor-basis on another stage
  run "$loc" "$emit" --stage Implementation --model m --floor-basis 'stronger model' --effort high
  [ "$rc" -eq 2 ] && [ -z "$out" ] || fail "S236 AC1 [$loc] — a floor-basis on Implementation must still be refused when --effort follows it (exit 2, empty stdout), got rc=$rc out='$out'"
  # ... nor excuse a Review without one, whatever the order
  run "$loc" "$emit" --stage Review --model m --effort high
  [ "$rc" -eq 2 ] && [ -z "$out" ] || fail "S236 AC1 [$loc] — a Review without a floor-basis must still be refused with --effort present (exit 2, empty stdout), got rc=$rc out='$out'"
  # no --effort: no warning (a clean prompt is silent)
  run "$loc" "$emit" --stage Planning --model m
  [ "$rc" -eq 0 ] && [ -z "$err" ] || fail "S236 AC1 [$loc] — without --effort stderr must be empty, got rc=$rc err='$err'"
  # a refusal for another reason still refuses, whatever --effort says
  run "$loc" "$emit" --stage planning --model m --effort high
  [ "$rc" -eq 2 ] && [ -z "$out" ] || fail "S236 AC1 [$loc] — a bad stage with --effort must still be refused (exit 2, empty stdout), got rc=$rc out='$out'"
done
# the gate reads an emitter line next to a legacy one: no finding either way
rm -f "${FAKE_GH_DATA:?}"/*.json
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: x" "Closes #239"
json_comments "$FAKE_GH_DATA/reviews-246.json"
json_comments "$FAKE_GH_DATA/comments-239.json" "$("$emit" --stage Discovery --model m --effort high 2>/dev/null)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$("$emit" --stage Planning --model m 2>/dev/null)" "$("$emit" --stage Test --model m 2>/dev/null)" \
  '<!-- model-record: stage=Implementation model="m" effort="high" -->' \
  "$("$emit" --stage Review --model m --effort low --floor-basis 'same model, nothing else' 2>/dev/null)"
rf_out="$(cd "$RF_PLAIN" && PATH="$RF_BIN:$PATH" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)"
[ -z "$rf_out" ] || fail "S236 AC1 gate — effort-free emitter lines beside a legacy-effort line must give no finding, got: '$rf_out'"

test_done
