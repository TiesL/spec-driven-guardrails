#!/usr/bin/env bash
# S246 — rec_field reads attributes by a left-to-right walk: first occurrence wins, a value ending in ` name=` is never an attribute, a name that merely ends in another is not that attribute (R5, moved from S188)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC3; A31a ("Fields: a walk, not a search": each
# step consumes exactly one <blanks>name="value" from the front of the rest,
# the first occurrence of a name wins; Phase 1b's "the first <blank>name=" is
# the attribute" is withdrawn). The QA critique D2 and the Developer critique
# D1 gave the counter-example: on a strict-valid line a value may end in
# ` floor-basis=`, whose closing quote then looks like the opening quote of a
# different attribute; a first-match search returns ` floor-basis=` there and
# the non-blank wrong value would hide a missing floor-basis.
#
# Seam: rec_field <line> <name> on an ok line (the line field of an ok row, or
# a literal strict line), prints the value, nothing when the attribute is
# absent. This case also takes over the hijack arms of S188 (the `marker_attr`
# tests with `floor-basis="beats model="` and the like, retired there): every
# line below is a STRICT line (model first), because the reader's input is an
# ok line; the S188 arms that put floor-basis before model or put `>` or `<` or
# `-->` in a value describe lines that v2 does not read as ok (a near-miss, S243).
#
# Threat model: ACCIDENTAL, plus one deliberate shape a typed line can have
# (the emitter cannot produce a value ending in ` name=` for model, and a
# floor-basis ending in one is the same defect): a typed or legacy line whose
# value ends in an attribute name. The property arm below generates such lines.
#
# Locales: C, UTF8 and LANG (LC_ALL unset). A value with an invalid byte must
# come back byte for byte under all three (bash 3.2 `[[ =~ ]]` and BWK awk
# disagree about invalid bytes in a UTF-8 locale unless matching runs under C).
#
# Red today: stubs (return 99). Mutations this case must not survive (kill
# table): a first-match search (`[[:blank:]]name="([^"]*)"` on the whole line);
# an unanchored name match (`model` inside `reviewer-model`); the LAST
# occurrence instead of the first; a walk that stops at the first attribute;
# a name taken as a regex (`mo.el`, `.*`); evaluating a value ($(...)).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S246" || test_done
cd "$SANDBOX" || exit 1

# f <label> <line> <name> <want>: rec_field under every locale mode
f() {
  local label="$1" line="$2" name="$3" want="$4" mode
  for mode in $RH_MODES; do
    rh_expect_field "S246/$label" "$mode" "$line" "$name" "$want"
  done
}
# f_absent <label> <line> <name>: nothing on stdout
f_absent() {
  local label="$1" line="$2" name="$3" mode
  for mode in $RH_MODES; do
    rh_field "$mode" "$line" "$name"
    [ -z "$RH_OUT" ] || fail "S246/$label [$mode] — rec_field '$name' must print nothing for an absent attribute, got '$RH_OUT'"
  done
}

R='<!-- model-record: stage='

# --- AC3: the literal case ---------------------------------------------------
ac3="${R}Review model=\"x\" effort=\"see floor-basis=\" floor-basis=\"the real one\" -->"
f "AC3 floor-basis" "$ac3" floor-basis "the real one"
f "AC3 effort" "$ac3" effort "see floor-basis="
f "AC3 model" "$ac3" model "x"

# --- the hijack class, in every position and for every name ---------------------
l="${R}Review model=\"a\" floor-basis=\"beats model=\" effort=\"low\" -->"
f "floor-basis ending in ' model=' (from S188)" "$l" model a
f "floor-basis ending in ' model=' keeps its own value" "$l" floor-basis "beats model="
f "effort after it" "$l" effort low
l="${R}Review model=\"opus\" floor-basis=\"slower effort=\" effort=\"high\" -->"
f "floor-basis ending in ' effort=' (from S188)" "$l" effort high
f "floor-basis ending in ' effort=' keeps its own value" "$l" floor-basis "slower effort="
l="${R}Review model=\"m\" floor-basis=\"uses model= and effort= words\" -->"
f "model= and effort= inside a value (from S188)" "$l" model m
f_absent "no effort inside a value" "$l" effort
f "inside a value, kept whole" "$l" floor-basis "uses model= and effort= words"
l="${R}Review model=\"m\" a=\"x b=\" b=\"y c=\" c=\"z\" -->"
f "a chain: each value ends in the next name (a)" "$l" a "x b="
f "a chain (b)" "$l" b "y c="
f "a chain (c)" "$l" c z
l="${R}Review model=\"Claude floor-basis=\" effort=\"low\" -->"
f "the MODEL ends in ' floor-basis=' (Reviewer D3)" "$l" model "Claude floor-basis="
f_absent "so floor-basis is absent, not ' effort='" "$l" floor-basis
f "and effort is its own" "$l" effort low
l="${R}Review model=\"m\" effort=\"a floor-basis=\" note=\"b floor-basis=\" floor-basis=\"real\" -->"
f "two false starts before the real one" "$l" floor-basis real

# --- names: exact, never a suffix, never a prefix, never a regex ----------------
l="${R}Review model=\"sonnet\" reviewer-model=\"opus\" peak-effort=\"high\" effort=\"low\" -->"
f "reviewer-model after model (from S188)" "$l" model sonnet
f "reviewer-model by its own name" "$l" reviewer-model opus
f "peak-effort before effort (from S188)" "$l" effort low
f "peak-effort by its own name" "$l" peak-effort high
l="${R}Review model=\"sonnet\" same-model=\"opus\" effort=\"low\" max-effort=\"high\" -->"
f "same-model after model (from S188)" "$l" model sonnet
f "max-effort after effort (from S188)" "$l" effort low
l="${R}Review model=\"opus\" xmodel=\"x\" xeffort=\"high\" effort=\"low\" -->"
f "xmodel after model (from S188)" "$l" model opus
f "xeffort before effort (from S188)" "$l" effort low
l="${R}Review model=\"m\" old-floor-basis=\"x\" -->"
f_absent "floor-basis not matched inside old-floor-basis (from S188)" "$l" floor-basis
f "old-floor-basis by its own name" "$l" old-floor-basis x
l="${R}Review model=\"m\" x-model=\"opus\" -->"
f "model is the first, not x-model" "$l" model m
l="${R}Review model=\"m\" floor-basis=\"f\" -->"
f_absent "a regex-looking name" "$l" 'mo.el'
f_absent "a dot-star name" "$l" '.*'
f_absent "a name with a bracket" "$l" 'm[o]del'
f_absent "an empty name" "$l" ''
f_absent "an upper-case name" "$l" MODEL
f_absent "a name with a trailing equals sign" "$l" 'model='
f_absent "a name that is a prefix" "$l" 'floor'
f_absent "a name that is a prefix of a longer one" "$l" 'floor-basi'

# --- first occurrence wins -----------------------------------------------------
l="${R}Test model=\"m1\" effort=\"a\" effort=\"b\" same-model-exception=\"p\" effort=\"c\" -->"
f "duplicate attribute: the first (effort)" "$l" effort a
f "after the duplicate the walk goes on" "$l" same-model-exception p
l="${R}Review model=\"first\" floor-basis=\"one\" floor-basis=\"two\" -->"
f "duplicate floor-basis" "$l" floor-basis one
f "a repeated model attribute: the first" "${R}Planning model=\"first\" model=\"second\" -->" model first

# --- values: empty, with equals signs, metacharacters, bytes ---------------------
l="${R}Review model=\"m\" floor-basis=\"\" effort=\"e\" -->"
f "an empty value is empty and the walk goes on" "$l" effort e
f "an empty floor-basis prints nothing" "$l" floor-basis ""
l="${R}Review model=\"m\" floor-basis=\"a=b c= d==e\" -->"
f "equals signs inside a value" "$l" floor-basis "a=b c= d==e"
l="${R}Review model=\"m\" floor-basis=\"\$(touch pwned) \`touch pwned2\` \$HOME * ?\" -->"
f "a value is data, never evaluated" "$l" floor-basis "\$(touch pwned) \`touch pwned2\` \$HOME * ?"
[ ! -e "$SANDBOX/pwned" ] && [ ! -e "$SANDBOX/pwned2" ] || fail "S246 — a value was executed"
l="${R}Review model=\"m\" floor-basis=\"$(printf 'a\377b\342\200c\200d')\" effort=\"after\" -->"
f "invalid and truncated UTF-8 in a value" "$l" floor-basis "$(printf 'a\377b\342\200c\200d')"
f "the attribute after an invalid byte" "$l" effort after
f "a model with a legacy space and a long value" "${R}Implementation model=\"Claude Sonnet 5 (new)\" -->" model "Claude Sonnet 5 (new)"
f "tabs between attributes" "$(printf '%sReview\tmodel="m"\tfloor-basis="f"\t-->' "$R")" floor-basis f
f "trailing blanks after the closing arrow" "$(printf '%sReview model="m" floor-basis="f" -->  \t' "$R")" floor-basis f

# --- the pipeline-override kind ---------------------------------------------------
po='<!-- pipeline-override: decided-by="human" scope="skip=Test" reason="was scope=" -->'
f "override: decided-by" "$po" decided-by human
f "override: scope" "$po" scope "skip=Test"
f "override: a reason ending in ' scope='" "$po" reason "was scope="

# --- the property arm: generated lines whose values end in other names -------------
# A deterministic generator (a linear congruential generator in bash arithmetic:
# the same sequence on bash 3.2 and 5, no $RANDOM). Every expected value comes
# from the construction (first occurrence of each name), never from the reader.
seed=425
rnd() { # rnd <n>: sets RND to a number in 0..n-1
  seed=$(((seed * 1103515245 + 12345) & 2147483647))
  RND=$(((seed / 65536) % $1))
}
names=(floor-basis effort same-model-exception reviewer-model note x-1 a b)
pieces=("plain" "two words" "a=b" "x -- y" "" "é ✓" "*" "'q'" "a\\b" "-" "3")
# shellcheck disable=SC2329  # called through rh_run
rf_batch() { # rf_batch <line> <name>...: each value followed by U+001E
  local line="$1" n
  shift
  for n in "$@"; do
    rec_field "$line" "$n"
    printf '%s' "$RH_SEP"
  done
}
iter=0
bad=0
while [ "$iter" -lt 120 ] && [ "$bad" -lt 5 ]; do
  iter=$((iter + 1))
  rnd 6
  count=$((RND + 1))
  line="${R}Review model=\"mm\""
  seen=" "
  want=()
  for n in "${names[@]}"; do want+=(""); done
  k=0
  while [ "$k" -lt "$count" ]; do
    rnd "${#names[@]}"
    ni="$RND"
    name="${names[$ni]}"
    rnd 3
    if [ "$RND" -eq 0 ]; then
      rnd "${#names[@]}"
      val="see ${names[$RND]}="                   # the hijack shape
    else
      rnd "${#pieces[@]}"
      val="${pieces[$RND]}"
    fi
    line="$line $name=\"$val\""
    case "$seen" in
      *" $name "*) : ;;
      *) seen="$seen$name "; want[ni]="$val" ;;
    esac
    k=$((k + 1))
  done
  line="$line -->"
  for mode in C "${RH_MODES##* }"; do
    rh_run "$mode" rf_batch "$line" "${names[@]}"
    if [ "$RH_RC" -ne 0 ]; then
      fail "S246/property #$iter [$mode] — rec_field exited $RH_RC on: $line"
      bad=$((bad + 1))
      continue
    fi
    rest="$RH_OUT"
    ni=0
    for n in "${names[@]}"; do
      got="${rest%%"$RH_SEP"*}"
      rest="${rest#*"$RH_SEP"}"
      if [ "$got" != "${want[$ni]}" ]; then
        fail "S246/property #$iter [$mode] — rec_field '$n' gave '$got', want '${want[$ni]}' on: $line"
        bad=$((bad + 1))
      fi
      ni=$((ni + 1))
    done
  done
done
[ "$iter" -ge 100 ] || fail "S246/property — stopped after $iter lines (5 failures reached): the walk is wrong, see above"

test_done
