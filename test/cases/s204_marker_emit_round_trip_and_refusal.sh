#!/usr/bin/env bash
# S204 — model-record-emit.sh prints the one valid marker line, which rec_scan and rec_field read back field by field (and today's parser reads too), or prints nothing (E1 and E2)
# Covers: F40
#
# Issue #402 (A26), reduced to the model by #424 (no effort), rewritten on E1 and
# E2 by issue #425 (slice V4 of #411; A33 as amended by A33a, the QA critique D9).
# Seam: the wrapper skills/pre-merge-review/model-record-emit.sh (stdout, stderr,
# exit status); the lib's marker_emit agrees with it; the NEW reader
# (rec_scan, rec_field) is the judge of the round trip, with today's parser
# (marker_find, marker_attr) as the second judge (the issue: everything the
# emitter prints is also read by today's parser, so the old callers stay
# green); the gate is the end-to-end judge; the wrapper is run through a
# symlinked skills directory (an adopted project) and without the lib.
#
# E1 (the round trip) pins LITERAL lines: every accepted input has its expected
# output spelled out here, `<!-- model-record: stage=<S> model="<M>"[
# floor-basis="<F>"] -->`, so a bug shared by the emitter and the reader that
# judges it cannot pass (QA critique D9). E2 (refusal): exit 2 and EMPTY stdout
# and a reason on stderr for each refused input of A33a: the model (empty, over
# 200 BYTES, anything outside [A-Za-z0-9._:@/+-]); the floor-basis (`"`, `<`,
# `>`, every C0 control and DEL, the C1 controls U+0080 to U+009F as UTF-8 bytes,
# U+2028, U+2029, the bidirectional controls U+202A to U+202E and U+2066 to
# U+2069, a blank or empty one, over 500 BYTES); a floor-basis off Review and a
# Review without one; a bad stage; a flag value equal to a flag name; an unknown,
# missing, repeated or value-less flag, a positional argument. Boundaries:
# 500 bytes of floor-basis and 200 bytes of model are accepted, 501 and 201
# refused, in LC_ALL=C and in UTF-8 and with LC_ALL unset: 166 em dashes (498
# bytes) accepted, 167 (501) and 251 (753 bytes, 251 characters) refused, and
# 498 ASCII bytes plus one two-byte letter (500) accepted, 499 plus it (501)
# refused (the `${#var}` characters-versus-bytes class that only macOS showed in
# #405). Accepted although odd (a deny-list by design, A33a): NBSP, zero-width
# characters, U+200E, U+2027, U+202F, U+2065, U+206A, U+FFFD, and invalid or
# truncated UTF-8 (it reads back byte for byte; only its display suffers).
#
# Threat model: ACCIDENTAL defects (a bytes-versus-characters length test, a
# deny-list entry left out, a locale-dependent control-class test, a pattern that
# lets `<` or `>` through). Not a forger: the emitter cannot stop a role from
# typing a line instead of pasting it, and a typed strict line is byte-
# identical to emitter output (stated limit). The emitter's own internal round
# trip (print only what the reader reads back) is defence in depth; this case
# has no test that turns red only when it is removed (a mutation-only check:
# the refusals below are each judged on their input, not on the round trip).
#
# --effort is accepted and ignored (S236 owns it); one arm here shows a stale
# prompt still gets the literal line.
#
# Retired from the old S204: the old-parser-only round-trip assertions
# (marker_find/marker_attr as the sole judge), and the arms that ACCEPTED `>`,
# `<`, `-->` or `<!--` in a floor-basis (they are refusals now: E2). Kept: the
# symlinked skills directory, the missing lib (exit 3), the gate as judge, the
# refusal matrix for flags, stage, model, blank and over-long values.
#
# Red today: the E2 arms for `<`, `>`, C1, the line separators, the bidirectional
# controls, the byte limits and the flag-name rule fail (the emitter accepts
# them), and every rec_scan/rec_field judgement fails on the stubs. Mutations
# this case must not survive (kill table): drop `<` or `>` from the deny-list;
# test the length in characters; drop one C1, bidi or line-separator entry; a
# control-class test that depends on the locale; the flag-name rule dropped or
# widened to every `--` value; the literal output line changed.

# shellcheck disable=SC2059,SC2016  # the byte strings are printf formats on purpose (octal escapes); '$(touch pwned)' is a refused model, not an expansion
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

emit="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-emit.sh"
lib="$TEST_REPO_ROOT/lib/model-record.sh"
if [ ! -x "$emit" ]; then
  fail "S204 — skills/pre-merge-review/model-record-emit.sh is missing or not executable"
  test_done
fi
[ -f "$lib" ] || { fail "S204 — lib/model-record.sh is missing"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S204 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rh_init "S204" || test_done
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
: "$rf_status"

# the emitter's environments: the same three as the reader's (RH_MODES)
modes="$RH_MODES"
modes2="C"
case "$modes" in *LANG*) modes2="C LANG" ;; esac   # the exhaustive byte loops run in C and LANG only

SEP=$'\036'
# run <mode> <emit path> args...: sets out, err, rc
run() {
  local mode="$1" path="$2"
  shift 2
  case "$mode" in
    C) out="$(env -u LANG LC_ALL=C "$path" "$@" 2>"$SANDBOX/err")" ;;
    UTF8) out="$(env LC_ALL="$MD_UTF8" LANG="$MD_UTF8" "$path" "$@" 2>"$SANDBOX/err")" ;;
    LANG) out="$(env -u LC_ALL LANG="$MD_UTF8" "$path" "$@" 2>"$SANDBOX/err")" ;;
  esac
  rc=$?
  err="$(cat "$SANDBOX/err")"
}

# ---------------------------------------------------------------------------
# E1: the round trip, literal lines, judged by the new reader and the old one
# ---------------------------------------------------------------------------
# round_trip <label> <stage> <model> [<floor-basis>]: the wrapper in every mode
round_trip() {
  local label="$1" stage="$2" model="$3" fb="${4-}" have=0 want mode got
  [ "$#" -ge 4 ] && have=1
  want="<!-- model-record: stage=$stage model=\"$model\""
  [ "$have" -eq 0 ] || want="$want floor-basis=\"$fb\""
  want="$want -->"
  for mode in $modes; do
    if [ "$have" -eq 1 ]; then
      run "$mode" "$emit" --stage "$stage" --model "$model" --floor-basis "$fb"
    else
      run "$mode" "$emit" --stage "$stage" --model "$model"
    fi
    [ "$rc" -eq 0 ] || { fail "S204 round-trip/$label [$mode] — a valid input was refused (exit $rc): $err"; continue; }
    [ -z "$err" ] || fail "S204 round-trip/$label [$mode] — a valid call without --effort must print nothing on stderr, got: '$err'"
    [ "$out" = "$want" ] || { fail "S204 round-trip/$label [$mode] — the line must be exactly (literal) '$want', got: '$out'"; continue; }
    case "$out" in *' effort="'*) fail "S204 round-trip/$label [$mode] — the line must carry no effort attribute (#424): '$out'" ;; esac
    # the NEW reader: one ok row, the line verbatim, each field byte for byte
    rh_scan "S204 round-trip/$label" "$mode" model-record "$out" || continue
    if [ "$RH_N" -ne 1 ] || [ "$(rh_classes)" != ok ] || [ "${RH_STG[0]}" != "$stage" ] || [ "${RH_TXT[0]}" != "$out" ]; then
      fail "S204 round-trip/$label [$mode] — rec_scan must give exactly one ok row for stage $stage holding the line, got $RH_N rows '$(rh_classes)'"
    fi
    rh_expect_field "S204 round-trip/$label" "$mode" "$out" model "$model"
    if [ "$have" -eq 1 ]; then
      rh_expect_field "S204 round-trip/$label" "$mode" "$out" floor-basis "$fb"
    else
      rh_expect_field "S204 round-trip/$label (no floor-basis)" "$mode" "$out" floor-basis ""
    fi
    rh_expect_field "S204 round-trip/$label (no effort)" "$mode" "$out" effort ""
    # today's parser reads it too (the old callers stay green until they move)
    got="$(marker_find "$stage" "$out$SEP")"
    [ "$got" = "$out" ] || fail "S204 round-trip/$label [$mode] — today's marker_find does not return the emitted line: '$got'"
    got="$(marker_scan "$out$SEP")"
    case "$got" in
      "ok"$'\t'"$stage"$'\t'*) : ;;
      *) fail "S204 round-trip/$label [$mode] — today's marker_scan must say ok for the stage, got: '$got'" ;;
    esac
    [ "$(marker_attr "$out" model)" = "$model" ] || fail "S204 round-trip/$label [$mode] — today's marker_attr read model as '$(marker_attr "$out" model)'"
    if [ "$have" -eq 1 ]; then
      [ "$(marker_attr "$out" floor-basis)" = "$fb" ] || fail "S204 round-trip/$label [$mode] — today's marker_attr read floor-basis as '$(marker_attr "$out" floor-basis)'"
    fi
  done
}
# marker_find, marker_scan and marker_attr (today's parser) are still in the lib
# that rh_init sourced.

models=("claude-opus-5-5" "claude-haiku-4-5-20251001" "us.anthropic.claude-opus-4:0" "anthropic/claude-3.5@v1+x" "opus" "gpt-4o" "a" "-x")
long_model="$(printf 'a%.0s' $(seq 1 200))"
for st in Discovery Planning Test Implementation; do
  round_trip "$st" "$st" "claude-opus-5-5"
done
for m in "${models[@]}" "$long_model"; do
  round_trip "model ${m:0:30}" Planning "$m"
done
round_trip "Review" Review "claude-opus-5-5" "same model, higher judgment"
fbs=(
  "same model as Implementation, stronger judgment"
  "it's a mechanical rename"
  "a -- b"
  "model=x and floor-basis=y inside"
  "beats model="
  "ends in floor-basis="
  "a=b c= d==e"
  "stronger — mécanique ✓ ≥ Implementation"
  "ends with a dash -"
  "-- leading dashes are allowed"
  "the \$HOME and \$(x) and a backtick \` and * and ? and [ and % and \\ stay literal"
  "a   b"
)
i=0
for fb in "${fbs[@]}"; do
  i=$((i + 1))
  round_trip "Review floor-basis #$i" Review "claude-opus-5-5" "$fb"
done
# the deny-list is a deny-list by design (A33a): other code points are accepted
for u in '\302\240' '\302\241' '\342\200\213' '\342\200\214' '\342\200\215' '\342\200\216' '\342\200\217' '\342\200\247' '\342\200\257' '\342\201\240' '\342\201\245' '\342\201\252' '\357\273\277' '\357\277\275' '\360\237\230\200'; do
  b="$(printf "a${u}b")"
  round_trip "accepted code point $u" Review "claude-opus-5-5" "$b"
done
# invalid and truncated UTF-8 are accepted and read back byte for byte (A33)
for u in '\377' '\342\200' '\200' '\300\257' '\355\240\200'; do
  round_trip "invalid UTF-8 $u" Review "claude-opus-5-5" "$(printf "a${u}b")"
done
# the limits, in BYTES: 500 accepted (and 501 is E2 below)
fb500="$(printf 'x%.0s' $(seq 1 500))"
round_trip "500 ASCII bytes" Review "claude-opus-5-5" "$fb500"
round_trip "166 em dashes (498 bytes)" Review "claude-opus-5-5" "$(for _ in $(seq 1 166); do printf '\342\200\224'; done)"
round_trip "498 ASCII bytes plus one two-byte letter (500 bytes)" Review "claude-opus-5-5" "$(printf 'x%.0s' $(seq 1 498))$(printf '\303\251')"
round_trip "250 two-byte letters (500 bytes, 250 characters)" Review "claude-opus-5-5" "$(for _ in $(seq 1 250); do printf '\303\251'; done)"

# the library function agrees with the wrapper
type marker_emit >/dev/null 2>&1 || fail "S204 — lib/model-record.sh defines no marker_emit"
if type marker_emit >/dev/null 2>&1; then
  lib_out="$(marker_emit Planning claude-opus-5-5 2>/dev/null)"
  run C "$emit" --stage Planning --model claude-opus-5-5
  [ -n "$lib_out" ] && [ "$lib_out" = "$out" ] || fail "S204 — marker_emit and the wrapper disagree: '$lib_out' vs '$out'"
  lib_review="$(marker_emit Review claude-opus-5-5 'stronger model' 2>/dev/null)"
  [ "$lib_review" = '<!-- model-record: stage=Review model="claude-opus-5-5" floor-basis="stronger model" -->' ] \
    || fail "S204 — marker_emit Review <model> <floor-basis> must print the literal line, got: '$lib_review'"
  bad_out="$(marker_emit planning claude-opus-5-5 2>/dev/null)"
  bad_rc=$?
  [ "$bad_rc" -ne 0 ] && [ -z "$bad_out" ] || fail "S204 — marker_emit must refuse a bad stage with a non-zero status and empty stdout (rc=$bad_rc out='$bad_out')"
  gt_out="$(marker_emit Review claude-opus-5-5 'a > b' 2>/dev/null)"
  gt_rc=$?
  [ "$gt_rc" -ne 0 ] && [ -z "$gt_out" ] || fail "S204 — marker_emit must refuse a '>' in the floor-basis (rc=$gt_rc out='$gt_out')"
fi

# a stale prompt that still passes --effort gets the literal line (S236 owns the details)
run C "$emit" --stage Review --model claude-opus-5-5 --effort high --floor-basis "stronger judgment"
[ "$rc" -eq 0 ] && [ "$out" = '<!-- model-record: stage=Review model="claude-opus-5-5" floor-basis="stronger judgment" -->' ] \
  || fail "S204 — a stale --effort must still give the literal line, got rc=$rc out='$out'"

# five emitted lines make a gate run with no finding at all (the gate is the end-to-end judge)
fiveline() { "$emit" --stage "$1" --model claude-opus-5-5; }
rm -f "${FAKE_GH_DATA:?}"/*.json
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: x" "Closes #239"
json_comments "$FAKE_GH_DATA/reviews-246.json"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(fiveline Discovery)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(fiveline Planning)" "$(fiveline Test)" "$(fiveline Implementation)" \
  "$("$emit" --stage Review --model claude-opus-5-5 --floor-basis "stronger; the diff is small -- mechanical, model=x, it's fine")"
for mode in $modes; do
  case "$mode" in
    C) rf_out="$(cd "$RF_PLAIN" && env -u LANG LC_ALL=C PATH="$RF_BIN:$PATH" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)" ;;
    UTF8) rf_out="$(cd "$RF_PLAIN" && env LC_ALL="$MD_UTF8" LANG="$MD_UTF8" PATH="$RF_BIN:$PATH" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)" ;;
    LANG) rf_out="$(cd "$RF_PLAIN" && env -u LC_ALL LANG="$MD_UTF8" PATH="$RF_BIN:$PATH" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)" ;;
  esac
  [ -z "$rf_out" ] || fail "S204 gate [$mode] — five emitted markers must give no finding, got: '$rf_out'"
done

# ---------------------------------------------------------------------------
# E2: refusal: nothing on stdout, a reason on stderr, exit 2
# ---------------------------------------------------------------------------
refuse() { # label, args...   (every mode)
  local label="$1" mode
  shift
  for mode in $modes; do
    run "$mode" "$emit" "$@"
    [ "$rc" -eq 2 ] || fail "S204 refuse/$label [$mode] — expected exit 2, got $rc (stdout: '$out')"
    [ -z "$out" ] || fail "S204 refuse/$label [$mode] — a refusal must print NOTHING on stdout, got: '$out'"
    [ -n "$err" ] || fail "S204 refuse/$label [$mode] — a refusal must say why on stderr"
  done
}
refuse_fb() { # label, floor-basis   (every mode)
  refuse "$1" --stage Review --model claude-opus-5-5 --floor-basis "$2"
}
refuse_fb2() { # label, floor-basis   (modes C and LANG: the exhaustive loops)
  local label="$1" mode
  for mode in $modes2; do
    run "$mode" "$emit" --stage Review --model claude-opus-5-5 --floor-basis "$2"
    if [ "$rc" -ne 2 ] || [ -n "$out" ] || [ -z "$err" ]; then
      fail "S204 refuse/$label [$mode] — expected exit 2, empty stdout and a reason; got rc=$rc out='$out' err='$err'"
    fi
  done
}
base_ok=(--model claude-opus-5-5)
for st in planning Plan "" '"Planning"' 'Planning ' ' Planning' PLANNING 'Planning,Test'; do
  refuse "stage '$st'" --stage "$st" "${base_ok[@]}"
done
refuse "model empty" --stage Planning --model ""
refuse "model with a quote" --stage Planning --model 'claude"x'
refuse "model with a space" --stage Planning --model 'claude opus'
refuse "model with a newline" --stage Planning --model $'claude\nopus'
refuse "model with a tab" --stage Planning --model $'claude\topus'
refuse "model with an equals sign" --stage Planning --model 'a=b'
refuse "model with a closing arrow" --stage Planning --model 'a-->b'
refuse "model with < and >" --stage Planning --model 'a<b>c'
refuse "model with a command substitution" --stage Planning --model '$(touch pwned)'
[ ! -e "$SANDBOX/pwned" ] && [ ! -e ./pwned ] || fail "S204 — a model value was executed"
refuse "model over 200 bytes (201)" --stage Planning --model "${long_model}a"
refuse "model with a non-ASCII letter" --stage Planning --model "$(printf 'cl\303\251')"
refuse "Review without a floor-basis" --stage Review "${base_ok[@]}"
refuse "Review with an empty floor-basis" --stage Review "${base_ok[@]}" --floor-basis ""
refuse "Review with a blank floor-basis" --stage Review "${base_ok[@]}" --floor-basis "   "
for st in Discovery Planning Test Implementation; do
  refuse "floor-basis on $st" --stage "$st" "${base_ok[@]}" --floor-basis "same model, higher judgment"
done

# the deny-list of A33a, one input each
refuse_fb "floor-basis with a double quote" 'he said "ok"'
refuse_fb "floor-basis with <" 'a < b'
refuse_fb "floor-basis with >" 'stronger > weaker'
refuse_fb "floor-basis with -->" 'ends with --> inside'
refuse_fb "floor-basis with <!--" 'has <!-- an opener'
refuse_fb "floor-basis with a newline" $'line one\nline two'
refuse_fb "floor-basis with a tab" $'a\tb'
refuse_fb "floor-basis with U+001E" "a${SEP}b"
refuse_fb "floor-basis with DEL" $'a\177b'
refuse_fb "floor-basis with CR" $'a\rb'
b=1
while [ "$b" -le 31 ]; do
  printf -v val 'a%bb' "\\0$(printf '%03o' "$b")"   # printf -v keeps a newline that $(...) would trim
  refuse_fb2 "floor-basis with C0 byte $b" "$val"
  b=$((b + 1))
done
# C1 controls U+0080 to U+009F, as UTF-8 bytes C2 80 to C2 9F
b=128
while [ "$b" -le 159 ]; do
  refuse_fb2 "floor-basis with the C1 control U+0$(printf '%03X' "$b")" "a$(printf '\302')$(printf '%b' "\\0$(printf '%03o' "$b")")b"
  b=$((b + 1))
done
refuse_fb2 "floor-basis with U+0085 (NEL)" "$(printf 'a\302\205b')"
refuse_fb2 "floor-basis with U+2028 (LS)" "$(printf 'a\342\200\250b')"
refuse_fb2 "floor-basis with U+2029 (PS)" "$(printf 'a\342\200\251b')"
# bidirectional controls U+202A to U+202E (E2 80 AA to AE) and U+2066 to U+2069 (E2 81 A6 to A9)
for u in '\342\200\252' '\342\200\253' '\342\200\254' '\342\200\255' '\342\200\256' '\342\201\246' '\342\201\247' '\342\201\250' '\342\201\251'; do
  refuse_fb2 "floor-basis with the bidirectional control $u" "$(printf "a${u}b")"
done

# the byte limits, in every mode: 501 bytes refused (the 500 boundary is accepted in E1)
refuse_fb "floor-basis of 501 ASCII bytes" "${fb500}x"
refuse_fb "251 em dashes (753 bytes, 251 characters)" "$(for _ in $(seq 1 251); do printf '\342\200\224'; done)"
refuse_fb "167 em dashes (501 bytes)" "$(for _ in $(seq 1 167); do printf '\342\200\224'; done)"
refuse_fb "499 ASCII bytes plus one two-byte letter (501 bytes)" "$(printf 'x%.0s' $(seq 1 499))$(printf '\303\251')"
refuse_fb "251 two-byte letters (502 bytes, 251 characters)" "$(for _ in $(seq 1 251); do printf '\303\251'; done)"

# flags
refuse "unknown flag" --stage Planning "${base_ok[@]}" --bogus x
refuse "positional argument" --stage Planning "${base_ok[@]}" extra
refuse "missing --stage" "${base_ok[@]}"
refuse "missing --model" --stage Planning
refuse "no arguments"
refuse "repeated --model" --stage Planning --model a --model b
refuse "repeated --stage" --stage Planning --stage Test "${base_ok[@]}"
refuse "repeated --floor-basis" --stage Review "${base_ok[@]}" --floor-basis a --floor-basis b
refuse "flag without a value" --stage Planning --model
refuse "a hand-typed quoted stage flag" '--stage="Planning"' "${base_ok[@]}"
# a flag value that IS a flag name (A33a; #404 item 3)
refuse "--model's value is --floor-basis" --stage Review --model --floor-basis --floor-basis "stronger"
refuse "--model's value is --stage" --stage Planning --model --stage
refuse "--stage's value is --model" --stage --model --model claude-opus-5-5
refuse "--floor-basis's value is --stage" --stage Review "${base_ok[@]}" --floor-basis --stage
refuse "--floor-basis's value is --effort" --stage Review "${base_ok[@]}" --floor-basis --effort
refuse "--floor-basis's value is --floor-basis" --stage Review "${base_ok[@]}" --floor-basis --floor-basis

# a refusal never leaves a partial line
run C "$emit" --stage Review --model 'x"y' --floor-basis ok
[ -z "$out" ] || fail "S204 — partial output on refusal: '$out'"

# ---------------------------------------------------------------------------
# the wrapper through a symlinked skills directory, and without the lib
# ---------------------------------------------------------------------------
linked="$SANDBOX/proj"
mkdir -p "$linked/.claude"
ln -s "$TEST_REPO_ROOT/skills" "$linked/.claude/skills"
for mode in $modes; do
  run "$mode" "$linked/.claude/skills/pre-merge-review/model-record-emit.sh" --stage Review --model claude-opus-5-5 --floor-basis "weaker model, mechanical rename"
  want='<!-- model-record: stage=Review model="claude-opus-5-5" floor-basis="weaker model, mechanical rename" -->'
  [ "$rc" -eq 0 ] && [ "$out" = "$want" ] \
    || fail "S204 symlink [$mode] — through .claude/skills (an adopted project) the wrapper must give the literal line, rc=$rc out='$out' err='$err'"
  rh_expect_field "S204 symlink" "$mode" "$out" floor-basis "weaker model, mechanical rename"
done
alone="$SANDBOX/alone/skills/pre-merge-review"
mkdir -p "$alone"
cp "$emit" "$alone/model-record-emit.sh"
run C "$alone/model-record-emit.sh" --stage Planning --model claude-opus-5-5
[ "$rc" -eq 3 ] && [ -z "$out" ] || fail "S204 — without lib/model-record.sh: expected exit 3 and empty stdout, got rc=$rc out='$out'"
grep -q 'model-record' <<<"$err" || fail "S204 — the missing-lib message must name lib/model-record.sh, got: '$err'"

test_done
