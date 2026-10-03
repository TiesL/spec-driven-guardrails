#!/usr/bin/env bash
# S204 — model-record-emit.sh prints the one valid marker line, or nothing.
# Covers: F40
#
# Issue #402, Architect A26 (amended) and the maintainer's acceptance test:
# nobody types a marker. `skills/pre-merge-review/model-record-emit.sh --stage
# <Stage> --model <id> --effort <low|medium|high|unknown> [--floor-basis
# <sentence>]` prints exactly one line the parser reads back unchanged, or
# prints NOTHING on stdout, a reason on stderr and exits 2 (3 when the lib is
# missing); never a malformed line. Seam: the wrapper's stdout, stderr and exit
# status; the shared parser (marker_find, marker_scan, marker_attr) as the
# judge of the round trip; the gate as the end-to-end judge. Run under
# LC_ALL=C and a UTF-8 locale, through the real path and through a symlinked
# skills directory (an adopted project). Decisions taken from A26's text: floor-basis
# is required for Review and refused elsewhere; `"`, control bytes and an
# empty or over-long text are refused; `-->` and `<!--` in a floor-basis are
# refused (GitHub would end the comment early), but the test accepts either a
# refusal or an exact round trip there, so only a malformed line fails.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

emit="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-emit.sh"
lib="$TEST_REPO_ROOT/lib/model-record.sh"
if [ ! -x "$emit" ]; then
  fail "S204 — skills/pre-merge-review/model-record-emit.sh is missing or not executable"
  test_done
fi
[ -f "$lib" ] || { fail "S204 — lib/model-record.sh is missing"; test_done; }
# shellcheck source=../../lib/model-record.sh disable=SC1091
. "$lib"
command -v jq >/dev/null 2>&1 || { fail "S204 — jq is needed by the fake gh"; test_done; }
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
[ -n "$utf8" ] || echo "    NOTE: S204 — no UTF-8 locale installed; only LC_ALL=C is exercised" >&2

SEP=$'\036'
# run <locale> <emit path> args...: sets out, err, rc
run() {
  local loc="$1" path="$2"
  shift 2
  out="$(LC_ALL="$loc" LANG="$loc" "$path" "$@" 2>"$SANDBOX/err")"
  rc=$?
  err="$(cat "$SANDBOX/err")"
}

# ---------------------------------------------------------------------------
# (1) round trip
# ---------------------------------------------------------------------------
round_trip() { # label locale path stage model effort [floor-basis]
  local label="$1" loc="$2" path="$3" stage="$4" model="$5" effort="$6" fb="${7-}" have=0 got
  [ "$#" -ge 7 ] && have=1
  if [ "$have" -eq 1 ]; then
    run "$loc" "$path" --stage "$stage" --model "$model" --effort "$effort" --floor-basis "$fb"
  else
    run "$loc" "$path" --stage "$stage" --model "$model" --effort "$effort"
  fi
  [ "$rc" -eq 0 ] || { fail "S204 round-trip/$label [$loc] — a valid input was refused (exit $rc): $err"; return; }
  [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] || { fail "S204 round-trip/$label [$loc] — expected exactly one line, got: '$out'"; return; }
  case "$out" in "<!-- model-record: stage=$stage "*" -->") : ;; *) fail "S204 round-trip/$label [$loc] — not a model-record marker with a bare stage: '$out'"; return ;; esac
  got="$(marker_find "$stage" "$out$SEP")"
  [ "$got" = "$out" ] || fail "S204 round-trip/$label [$loc] — marker_find does not return the emitted line: '$got' vs '$out'"
  [ "$(marker_attr "$out" model)" = "$model" ] || fail "S204 round-trip/$label [$loc] — model came back as '$(marker_attr "$out" model)', want '$model'"
  [ "$(marker_attr "$out" effort)" = "$effort" ] || fail "S204 round-trip/$label [$loc] — effort came back as '$(marker_attr "$out" effort)', want '$effort'"
  if [ "$have" -eq 1 ]; then
    [ "$(marker_attr "$out" floor-basis)" = "$fb" ] || fail "S204 round-trip/$label [$loc] — floor-basis came back as '$(marker_attr "$out" floor-basis)', want '$fb'"
  else
    [ -z "$(marker_attr "$out" floor-basis)" ] || fail "S204 round-trip/$label [$loc] — a floor-basis appeared from nowhere"
  fi
  got="$(marker_scan "$out$SEP")"
  case "$got" in
    "ok"$'\t'"$stage"$'\t'*) : ;;
    *) fail "S204 round-trip/$label [$loc] — marker_scan must say ok for the stage, got: '$got'" ;;
  esac
  [ "$(printf '%s\n' "$got" | grep -c .)" -eq 1 ] || fail "S204 round-trip/$label [$loc] — marker_scan found more than one marker: '$got'"
}

models=("claude-opus-5-5" "claude-haiku-4-5-20251001" "us.anthropic.claude-opus-4:0" "anthropic/claude-3.5@v1+x" "opus" "gpt-4o")
long_model="$(printf 'a%.0s' $(seq 1 200))"
fbs=(
  "same model as Implementation, higher effort"
  "stronger > weaker"
  "a < b"
  "it's a mechanical rename"
  "a -- b"
  "model=x and effort=high inside"
  "stronger — mécanique ✓ ≥ Implementation"
)
for loc in $locales; do
  for st in Discovery Planning Test Implementation; do
    for ef in low medium high unknown; do
      round_trip "$st/$ef" "$loc" "$emit" "$st" "claude-opus-5-5" "$ef"
    done
  done
  for m in "${models[@]}" "$long_model"; do
    round_trip "model ${m:0:30}" "$loc" "$emit" Planning "$m" medium
  done
  for ef in low medium high unknown; do
    round_trip "Review/$ef" "$loc" "$emit" Review "claude-opus-5-5" "$ef" "same model, higher effort"
  done
  i=0
  for fb in "${fbs[@]}"; do
    i=$((i + 1))
    round_trip "Review floor-basis #$i" "$loc" "$emit" Review "claude-opus-5-5" high "$fb"
  done
done

# the ambiguous floor-basis texts: either refused, or an exact round trip
for fb in "ends with --> inside" "has <!-- an opener"; do
  for loc in $locales; do
    run "$loc" "$emit" --stage Review --model claude-opus-5-5 --effort high --floor-basis "$fb"
    if [ "$rc" -eq 0 ]; then
      [ "$(marker_attr "$out" floor-basis)" = "$fb" ] && [ "$(marker_scan "$out$SEP" | grep -c '^ok')" -eq 1 ] \
        || fail "S204 ambiguous/'$fb' [$loc] — emitted but the parser does not read it back: '$out'"
    else
      [ "$rc" -eq 2 ] && [ -z "$out" ] || fail "S204 ambiguous/'$fb' [$loc] — a refusal must be exit 2 with empty stdout, got rc=$rc out='$out'"
    fi
  done
done

# the library function agrees with the wrapper
type marker_emit >/dev/null 2>&1 || fail "S204 — lib/model-record.sh defines no marker_emit"
if type marker_emit >/dev/null 2>&1; then
  lib_out="$(marker_emit Planning claude-opus-5-5 low 2>/dev/null)"
  run C "$emit" --stage Planning --model claude-opus-5-5 --effort low
  [ "$lib_out" = "$out" ] || fail "S204 — marker_emit and the wrapper disagree: '$lib_out' vs '$out'"
  bad_out="$(marker_emit planning claude-opus-5-5 low 2>/dev/null)"
  bad_rc=$?
  [ "$bad_rc" -ne 0 ] && [ -z "$bad_out" ] || fail "S204 — marker_emit must refuse a bad stage with a non-zero status and empty stdout (rc=$bad_rc out='$bad_out')"
fi

# five emitted lines make a gate run with no finding at all
fiveline() { "$emit" --stage "$1" --model claude-opus-5-5 --effort "$2"; }
rm -f "${FAKE_GH_DATA:?}"/*.json
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: x" "Closes #239"
json_comments "$FAKE_GH_DATA/reviews-246.json"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(fiveline Discovery high)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(fiveline Planning high)" "$(fiveline Test medium)" "$(fiveline Implementation medium)" \
  "$("$emit" --stage Review --model claude-opus-5-5 --effort high --floor-basis 'stronger > weaker; the diff is small -- mechanical')"
for loc in $locales; do
  rf_out="$(cd "$RF_PLAIN" && PATH="$RF_BIN:$PATH" LC_ALL="$loc" LANG="$loc" "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)"
  [ -z "$rf_out" ] || fail "S204 gate [$loc] — five emitted markers (Review with '>' and '--' in its floor-basis) must give no finding, got: '$rf_out'"
done

# ---------------------------------------------------------------------------
# (2) refusal: nothing on stdout, a reason on stderr, exit 2
# ---------------------------------------------------------------------------
refuse() { # label, args...
  local label="$1"
  shift
  local loc
  for loc in $locales; do
    run "$loc" "$emit" "$@"
    [ "$rc" -eq 2 ] || fail "S204 refuse/$label [$loc] — expected exit 2, got $rc (stdout: '$out')"
    [ -z "$out" ] || fail "S204 refuse/$label [$loc] — a refusal must print NOTHING on stdout, got: '$out'"
    [ -n "$err" ] || fail "S204 refuse/$label [$loc] — a refusal must say why on stderr"
  done
}
base_ok=(--model claude-opus-5-5 --effort high)
for st in planning Plan "" '"Planning"' 'Planning ' ' Planning' PLANNING 'Planning,Test'; do
  refuse "stage '$st'" --stage "$st" "${base_ok[@]}"
done
for ef in Low max "" 'high ' session-default '"low"' 1; do
  refuse "effort '$ef'" --stage Planning --model claude-opus-5-5 --effort "$ef"
done
refuse "model empty" --stage Planning --model "" --effort low
refuse "model with a quote" --stage Planning --model 'claude"x' --effort low
refuse "model with a space" --stage Planning --model 'claude opus' --effort low
refuse "model with a newline" --stage Planning --model $'claude\nopus' --effort low
refuse "model with a tab" --stage Planning --model $'claude\topus' --effort low
refuse "model with an equals sign" --stage Planning --model 'a=b' --effort low
refuse "model with a closing arrow" --stage Planning --model 'a-->b' --effort low
refuse "model with a command substitution" --stage Planning --model '$(touch pwned)' --effort low
[ ! -e "$SANDBOX/pwned" ] && [ ! -e ./pwned ] || fail "S204 — a model value was executed"
refuse "model over 200 characters" --stage Planning --model "${long_model}a" --effort low
fb_ok="same model, higher effort"
refuse "Review without a floor-basis" --stage Review "${base_ok[@]}"
refuse "Review with an empty floor-basis" --stage Review "${base_ok[@]}" --floor-basis ""
refuse "Review with a blank floor-basis" --stage Review "${base_ok[@]}" --floor-basis "   "
refuse "floor-basis with a double quote" --stage Review "${base_ok[@]}" --floor-basis 'he said "ok"'
refuse "floor-basis with a newline" --stage Review "${base_ok[@]}" --floor-basis $'line one\nline two'
refuse "floor-basis with a tab" --stage Review "${base_ok[@]}" --floor-basis $'a\tb'
refuse "floor-basis with U+001E" --stage Review "${base_ok[@]}" --floor-basis "a${SEP}b"
refuse "floor-basis with a control byte" --stage Review "${base_ok[@]}" --floor-basis $'a\001b'
refuse "floor-basis with DEL" --stage Review "${base_ok[@]}" --floor-basis $'a\177b'
refuse "floor-basis over 500 bytes" --stage Review "${base_ok[@]}" --floor-basis "$(printf 'x%.0s' $(seq 1 501))"
for st in Discovery Planning Test Implementation; do
  refuse "floor-basis on $st" --stage "$st" "${base_ok[@]}" --floor-basis "$fb_ok"
done
# flags
refuse "unknown flag" --stage Planning "${base_ok[@]}" --bogus x
refuse "positional argument" --stage Planning "${base_ok[@]}" extra
refuse "missing --stage" "${base_ok[@]}"
refuse "missing --model" --stage Planning --effort low
refuse "missing --effort" --stage Planning --model claude-opus-5-5
refuse "no arguments"
refuse "repeated --model" --stage Planning --model a --model b --effort low
refuse "repeated --stage" --stage Planning --stage Test "${base_ok[@]}"
refuse "flag without a value" --stage Planning --model claude-opus-5-5 --effort
refuse "a hand-typed quoted stage flag" '--stage="Planning"' "${base_ok[@]}"

# a refusal never leaves a partial line
run C "$emit" --stage Review --model 'x"y' --effort low --floor-basis ok
[ -z "$out" ] || fail "S204 — partial output on refusal: '$out'"

# ---------------------------------------------------------------------------
# (3) the wrapper through a symlinked skills directory, and without the lib
# ---------------------------------------------------------------------------
linked="$SANDBOX/proj"
mkdir -p "$linked/.claude"
ln -s "$TEST_REPO_ROOT/skills" "$linked/.claude/skills"
for loc in $locales; do
  run "$loc" "$linked/.claude/skills/pre-merge-review/model-record-emit.sh" --stage Review --model claude-opus-5-5 --effort unknown --floor-basis "weaker model, mechanical rename"
  [ "$rc" -eq 0 ] && [ "$(marker_attr "$out" floor-basis)" = "weaker model, mechanical rename" ] \
    || fail "S204 symlink [$loc] — through .claude/skills (an adopted project) the wrapper must work, rc=$rc out='$out' err='$err'"
done
alone="$SANDBOX/alone/skills/pre-merge-review"
mkdir -p "$alone"
cp "$emit" "$alone/model-record-emit.sh"
run C "$alone/model-record-emit.sh" --stage Planning --model claude-opus-5-5 --effort low
[ "$rc" -eq 3 ] && [ -z "$out" ] || fail "S204 — without lib/model-record.sh: expected exit 3 and empty stdout, got rc=$rc out='$out'"
grep -q 'model-record' <<<"$err" || fail "S204 — the missing-lib message must name lib/model-record.sh, got: '$err'"

test_done
