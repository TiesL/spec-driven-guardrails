#!/usr/bin/env bash
# S249 — the property arm: every hostile byte or token at every position of a record, every byte class, a seeded generator with a fence oracle, and a scale case; every inserted record reads back exactly and nothing else is read (K2)
# Covers: F40
#
# Issue #425 (slice V4 of #411), A35a "K2, the property arm", QA critique Q3/D7.
# Seam: rec_scan_bundle (bulk) and rec_scan, rec_field. Four arms:
#   (a) structured injection: a valid Review record with a token inserted at each
#       position (the start, middle and end of the model, of the floor-basis and
#       of a legacy effort value; right before and right after the stage name;
#       inside an attribute name; between attributes; after the closing arrow), for
#       ~95 tokens: every C0 byte, DEL, `"` `<` `>` `-->` `<!--`, tab, LF, CR,
#       CRLF, `'` `\` backtick `$` `*` `?` `[` `%` `=`, a value ending in ` name=`,
#       a leading `-`, NEL, LS, PS, NBSP, BOM, zero-width, bidirectional controls,
#       U+FFFD, a 4-byte emoji, invalid and truncated UTF-8, overlong and surrogate
#       encodings. The expectation comes from a TWO-flag table of the grammar (is
#       the token a value byte, is it blank, does it end the line), never from the
#       reader. A hostile token gives exactly one near-miss row; a value byte
#       gives one ok row whose line is verbatim and whose value reads back; and
#       one valid sentinel record, before or after, is always ok.
#   (b) every single byte 0x01 to 0xFF (but LF, CR) as a floor-basis character:
#       ok exactly when the byte is not `"`, `<`, `>`, a C0 control or DEL.
#   (c) a deterministic generator (a linear congruential generator in bash
#       arithmetic, seed 425: the same sequence on bash 3.2 and 5, no $RANDOM) that
#       builds bodies of valid records, hostile lines, noise lines full of
#       delimiters and fence lines, with a small fence-state oracle; the
#       invariant is that the rows are exactly the oracle's: every valid record
#       outside a fence is read back verbatim, every hostile one is a near-miss,
#       everything inside a fence is quoted, noise gives nothing.
#   (d) scale: 60 bodies, one holding a 100 KB value (ok, read back) and one a
#       100 KB hostile line (a bounded near-miss); the time is reported, not failed.
#
# Threat model: ACCIDENTAL defects AND the deliberate injection shapes the #405
# rounds found (a `>` or quote or `-->` or U+001E or a multibyte byte at a value
# position). It does NOT model a forger who writes a strict line (no artifact can
# tell a typed strict line from emitter output; stated limit) and cannot carry
# NUL (a bash argument cannot hold it; stated limit). The framing layers of the
# callers (the gate's U+001E transport, the collector's \001) are not here: the
# callers move to this reader in V6 to V8 and bring their own framing arms then.
#
# Locales: C and LANG (`LC_ALL` unset, `LANG` UTF-8, the environment that
# exposes a missing per-command `LC_ALL=C`; QA critique D1/D3), the two hardest.
#
# Red today: stubs (return 99). Mutations this case must not survive (kill
# table, one per arm): drop one injection arm (e.g. stop refusing `<`, or a
# control byte, or DEL); forbid bytes 0x80-0xFF; allow a record to continue over
# a newline; a reader that aborts on invalid UTF-8 under LANG (no per-command
# LC_ALL=C); a fence strip that fails on `~~~` or on a longer closer; a reader
# that prints the whole 100 KB line.

# shellcheck disable=SC2016,SC1003,SC2329  # token strings are printf %b input, not expansions; read_back runs through rh_run
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S249" || test_done

mode_list="C"
case "$RH_MODES" in *LANG*) mode_list="C LANG" ;; esac

LF=$'\n'
valid_a="$(rh_rec Planning sentinel-a)"
oct() { printf '%b' "\\0$(printf '%03o' "$1")"; }   # one byte by value (%b with \0ooo: the same on bash 3.2 and 5)

# ============================================================================
# (a) structured injection arms
# ============================================================================
# token table: label | printf-format bytes | class
#   V   a value byte sequence (the reader accepts it inside a value)
#   H   hostile inside a value (a quote, <, >, a control byte, DEL, tab)
#   SP  a space   TAB a tab   NL a line ending (LF, CR, CRLF)   NC like V, and a valid attribute-name character
TL=(); TB=(); TC=()
tok() { TL+=("$1"); TB+=("$2"); TC+=("$3"); }
tok 'double quote' '"' H
tok 'less-than' '<' H
tok 'greater-than' '>' H
tok 'closing arrow' '-->' H
tok 'opening comment' '<!--' H
tok 'arrow and text' 'x --> y' H
tok 'a whole nested record' '<!-- model-record: stage=Test model=x -->' H
tok 'tab' '\t' TAB
tok 'space' ' ' SP
tok 'LF' '\n' NL
tok 'CR' '\r' NL
tok 'CRLF' '\r\n' NL
tok 'DEL' '\0177' H
b=1
while [ "$b" -le 31 ]; do
  case "$b" in
    9 | 10 | 13 | 30) : ;;    # tab, LF, CR above; U+001E only through rec_scan below
    *) tok "C0 byte $b" "$(printf '\\0%03o' "$b")" H ;;
  esac
  b=$((b + 1))
done
tok "single quote" "'" V
tok 'backslash' '\\' V
tok 'backtick' '`' V
tok 'dollar' '$' V
tok 'dollar-paren' '$(x)' V
tok 'star' '*' V
tok 'question' '?' V
tok 'bracket' '[' V
tok 'percent' '%' V
tok 'equals' '=' V
tok 'double dash' '--' NC
tok 'single dash' '-' NC
tok 'a value ending in a name' ' floor-basis=' V
tok 'a value ending in model=' ' model=' V
tok 'semicolon and pipe' ';|&' V
tok 'NEL' '\0302\0205' V
tok 'LS' '\0342\0200\0250' V
tok 'PS' '\0342\0200\0251' V
tok 'NBSP' '\0302\0240' V
tok 'BOM' '\0357\0273\0277' V
tok 'zero-width space' '\0342\0200\0213' V
tok 'RLO' '\0342\0200\0256' V
tok 'isolate' '\0342\0201\0246' V
tok 'FFFD' '\0357\0277\0275' V
tok 'em dash' '\0342\0200\0224' V
tok 'emoji' '\0360\0237\0230\0200' V
tok 'invalid 0xFF' '\0377' V
tok 'invalid 0xFE' '\0376' V
tok 'invalid 0xC0' '\0300' V
tok 'invalid 0xC1' '\0301' V
tok 'invalid 0xF5' '\0365' V
tok 'continuation 0x80' '\0200' V
tok 'continuation 0xBF' '\0277' V
tok 'truncated 2-byte' '\0302' V
tok 'truncated 3-byte' '\0342\0200' V
tok 'truncated 4-byte' '\0360\0237\0230' V
tok 'overlong slash' '\0300\0257' V
tok 'surrogate' '\0355\0240\0200' V
tok 'many 0xFF' '\0377\0377\0377\0377\0377\0377\0377\0377' V

# positions: name, build function body below. expectation: expect <pos> <class> -> ok | nm
expect() { # <pos> <class>
  local pos="$1" cls="$2"
  case "$pos" in
    model-s | model-m | model-e | fb-s | fb-m | fb-e | ef-m)
      case "$cls" in V | NC | SP) echo ok ;; *) echo nm ;; esac ;;
    stage-prefix | name)
      case "$pos:$cls" in name:NC) echo ok ;; *) echo nm ;; esac ;;
    stage-suffix | between)
      case "$cls" in SP | TAB) echo ok ;; *) echo nm ;; esac ;;
    after-arrow)
      case "$cls" in SP | TAB | NL) echo ok ;; *) echo nm ;; esac ;;
  esac
}
POSITIONS="model-s model-m model-e fb-s fb-m fb-e ef-m stage-prefix stage-suffix name between after-arrow"
# build <pos> <token bytes>: sets LINE, and WANT_MODEL, WANT_FB, WANT_EF (what the attributes read as when ok)
build() {
  local pos="$1" t="$2" m=m1 fb=fb1 ef=ef1 stage=Review sfx="" nm=floor-basis between="" after=""
  case "$pos" in
    model-s) m="${t}m1" ;;
    model-m) m="m${t}1" ;;
    model-e) m="m1${t}" ;;
    fb-s) fb="${t}fb1" ;;
    fb-m) fb="fb${t}1" ;;
    fb-e) fb="fb1${t}" ;;
    ef-m) ef="e${t}f" ;;
    stage-prefix) stage="${t}Review" ;;
    stage-suffix) sfx="$t" ;;
    name) nm="floor${t}-basis" ;;
    between) between=" $t " ;;
    after-arrow) after="$t" ;;
  esac
  WANT_MODEL="$m"; WANT_FB="$fb"; WANT_EF="$ef"; WANT_NM="$nm"
  LINE="<!-- model-record: stage=${stage}${sfx} model=\"${m}\"${between} ${nm}=\"${fb}\" effort=\"${ef}\" -->${after}"
}

# one bundle per ordering (hostile then sentinel, sentinel then hostile), one body per case
CASE_POS=(); CASE_TOK=(); CASE_EXP=(); CASE_LINE=(); CASE_RAW=(); CASE_M=(); CASE_FB=(); CASE_EF=(); CASE_NM=()
i=0
while [ "$i" -lt "${#TL[@]}" ]; do
  printf -v t '%b' "${TB[$i]}"   # printf -v keeps a trailing newline that $(...) would trim
  for pos in $POSITIONS; do
    build "$pos" "$t"
    CASE_POS+=("$pos"); CASE_TOK+=("${TL[$i]}"); CASE_EXP+=("$(expect "$pos" "${TC[$i]}")")
    verb="$LINE"
    if [ "$pos" = after-arrow ] && [ "${TC[$i]}" = NL ]; then verb="${LINE%"$t"}"; fi   # a line ending is not part of the line
    CASE_RAW+=("$LINE"); CASE_LINE+=("$verb"); CASE_M+=("$WANT_MODEL"); CASE_FB+=("$WANT_FB"); CASE_EF+=("$WANT_EF"); CASE_NM+=("$WANT_NM")
  done
  i=$((i + 1))
done
n_cases="${#CASE_POS[@]}"
fwd=(); rev=()
i=0
while [ "$i" -lt "$n_cases" ]; do
  fwd+=("${CASE_RAW[$i]}${LF}${valid_a}")
  rev+=("${valid_a}${LF}${CASE_RAW[$i]}")
  i=$((i + 1))
done
bundle_fwd="$(rh_join_bundle "${fwd[@]}")"
bundle_rev="$(rh_join_bundle "${rev[@]}")"

check_injection() { # <label> <mode> <order fwd|rev>
  local label="$1" mode="$2" order="$3" i idx want got bundle sidx hidx
  if [ "$order" = fwd ]; then bundle="$bundle_fwd"; else bundle="$bundle_rev"; fi
  rh_bundle "S249/$label" "$mode" model-record "$bundle" || return
  i=0
  while [ "$i" -lt "$n_cases" ]; do
    idx=$((i + 1))
    if [ "${CASE_EXP[$i]}" = ok ]; then want="ok"; else want="near-miss"; fi
    if [ "$order" = fwd ]; then want="$want ok"; else want="ok $want"; fi
    got="$(rh_classes_for "$idx")"
    if [ "$got" != "$want" ]; then
      fail "S249/$label [$mode] — token '${CASE_TOK[$i]}' at ${CASE_POS[$i]}: want '$want', got '$got'"
    else
      # which ok row is which: the hostile line comes first in 'fwd', second in 'rev'
      if [ "$order" = fwd ]; then hidx=1; sidx=2; [ "${CASE_EXP[$i]}" = ok ] || sidx=1; else hidx=2; sidx=1; fi
      [ "$(rh_text_for "$idx" ok "$sidx")" = "$valid_a" ] \
        || fail "S249/$label [$mode] — token '${CASE_TOK[$i]}' at ${CASE_POS[$i]}: the sentinel record is not read back verbatim"
      if [ "${CASE_EXP[$i]}" = ok ]; then
        [ "$(rh_text_for "$idx" ok "$hidx")" = "${CASE_LINE[$i]}" ] \
          || fail "S249/$label [$mode] — token '${CASE_TOK[$i]}' at ${CASE_POS[$i]}: the ok row is not the line verbatim"
      fi
    fi
    i=$((i + 1))
  done
  [ "$RH_N" -eq $((2 * n_cases)) ] || fail "S249/$label [$mode] — want $((2 * n_cases)) rows (one hostile-or-ok and one sentinel per body), got $RH_N: some body produced an extra or a missing row"
}
for mode in $mode_list; do
  check_injection "injection (hostile, then sentinel)" "$mode" fwd
  check_injection "injection (sentinel, then hostile)" "$mode" rev
done

# the ok cases read their values back (through rec_field, in one subshell per mode)
read_back() {
  local i got
  i=0
  while [ "$i" -lt "$n_cases" ]; do
    if [ "${CASE_EXP[$i]}" = ok ]; then
      got="$(rec_field "${CASE_LINE[$i]}" model)"; [ "$got" = "${CASE_M[$i]}" ] || echo "FAIL token '${CASE_TOK[$i]}' at ${CASE_POS[$i]}: model read as '$got', want '${CASE_M[$i]}'"
      got="$(rec_field "${CASE_LINE[$i]}" "${CASE_NM[$i]}")"; [ "$got" = "${CASE_FB[$i]}" ] || echo "FAIL token '${CASE_TOK[$i]}' at ${CASE_POS[$i]}: ${CASE_NM[$i]} read as '$got', want '${CASE_FB[$i]}'"
      got="$(rec_field "${CASE_LINE[$i]}" effort)"; [ "$got" = "${CASE_EF[$i]}" ] || echo "FAIL token '${CASE_TOK[$i]}' at ${CASE_POS[$i]}: effort read as '$got', want '${CASE_EF[$i]}'"
    fi
    i=$((i + 1))
  done
}
for mode in $mode_list; do
  rh_run "$mode" read_back
  [ "$RH_RC" -eq 0 ] || fail "S249/read back [$mode] — the checker exited $RH_RC ($RH_ERR)"
  while IFS= read -r row; do
    case "$row" in FAIL*) fail "S249/read back [$mode] — ${row#FAIL }" ;; esac
  done <<<"$RH_OUT"
done

# U+001E as a value byte: rec_scan only (a bundle removes the byte first)
sepline="<!-- model-record: stage=Review model=\"m1\" floor-basis=\"a${RH_SEP}b\" -->"
for mode in $mode_list; do
  rh_scan "S249/U+001E" "$mode" model-record "${sepline}${LF}${valid_a}" || continue
  [ "$(rh_classes)" = "near-miss ok" ] || fail "S249/U+001E [$mode] — want 'near-miss ok', got '$(rh_classes)'"
done

# ============================================================================
# (b) every single byte as one floor-basis character
# ============================================================================
bytes=()
bytes_exp=()
b=1
while [ "$b" -le 255 ]; do
  case "$b" in 10 | 13 | 30) b=$((b + 1)); continue ;; esac    # LF, CR: line endings (arm a); U+001E: transport (above)
  bytes+=("<!-- model-record: stage=Review model=\"m1\" floor-basis=\"a$(oct "$b")b\" -->${LF}${valid_a}")
  if [ "$b" -eq 34 ] || [ "$b" -eq 60 ] || [ "$b" -eq 62 ] || [ "$b" -le 31 ] || [ "$b" -eq 127 ]; then bytes_exp+=("near-miss ok"); else bytes_exp+=("ok ok"); fi
  b=$((b + 1))
done
bundle="$(rh_join_bundle "${bytes[@]}")"
for mode in $mode_list; do
  rh_bundle "S249/byte classes" "$mode" model-record "$bundle" || continue
  i=0
  while [ "$i" -lt "${#bytes[@]}" ]; do
    got="$(rh_classes_for $((i + 1)))"
    [ "$got" = "${bytes_exp[$i]}" ] || fail "S249/byte classes [$mode] — body $((i + 1)) (the byte is in the case table at index $i): want '${bytes_exp[$i]}', got '$got'"
    i=$((i + 1))
  done
done

# ============================================================================
# (c) the seeded generator with a fence oracle
# ============================================================================
seed=425
RND=0
rnd() { seed=$(((seed * 1103515245 + 12345) & 2147483647)); RND=$(((seed / 65536) % $1)); }
valid_pool=(
  "$(rh_rec Discovery claude-opus-5-5)"
  "$(rh_rec Planning 'Claude Sonnet 5')"
  "$(rh_rec Test m3 'effort="unknown"')"
  "$(rh_rec Implementation m4 'same-model-exception="x y"')"
  "$(rh_rec Review m5 'floor-basis="a -- b = c, d"')"
  "$(rh_rec Review m6 "floor-basis=\"$(printf 'a\342\200\224b \377 \302\205')\"")"
  "<!--model-record:stage=Test model=\"m7\"-->  "
  "$(printf '<!--\tmodel-record:\tstage=Review\tmodel="m8"\tfloor-basis="t"\t-->')"
)
hostile_pool=(
  '<!-- model-record: stage=Review model="m" floor-basis="a > b" -->'
  '<!-- model-record: stage=Review model="m" floor-basis="a < b" -->'
  '<!-- model-record: stage=Review model="m" floor-basis="a"b" -->'
  '<!-- model-record: stage=Review model="m" floor-basis="open -->'
  '<!-- model-record: stage="Review" model="m" -->'
  '<!-- model-record: stage=Review model=m -->'
  '<!-- model-record: stage=Review model="" -->'
  'Done. <!-- model-record: stage=Test model="m" -->'
  '<!-- model-record: stage=Test model="m" --> trailing'
  "$(printf '<!-- model-record: stage=Review model="m" floor-basis="a\001b" -->')"
  "$(printf '<!-- model-record: stage=\377Test model="m" -->')"
  '<!-- model-record: stage=Review model="m" floor-basis="x --> y" -->'
)
noise_pool=(
  'plain prose with no delimiters at all'
  'a " quote, a < less, a > greater, a -- dash and a --> arrow'
  '<!-- an ordinary comment --> and <!-- another'
  '| a | b | c |'
  '- a list item with <!-- finding:x status=open -->'
  'unicode é ✓ — and a bad byte '"$(printf '\377')"
  '<!-- model-record-gate: x -->'
  ''
  'the word model without the dash'
  '1. numbered'
)
fence_open=('```' '~~~' '````' '~~~~~' '```text')
gen_body() { # sets GEN_BODY and GEN_WANT (space separated classes) and GEN_OKS (the ok lines, one per US)
  local n k kind infence="" fence_close_char="" fence_len=0 line f
  GEN_BODY=""; GEN_WANT=""; GEN_OKS=""
  rnd 9; n=$((RND + 3))
  k=0
  while [ "$k" -lt "$n" ]; do
    rnd 10
    if [ "$RND" -le 2 ]; then kind=V
    elif [ "$RND" -le 4 ]; then kind=H
    elif [ "$RND" -le 7 ]; then kind=N
    else kind=F; fi
    case "$kind" in
      V) rnd "${#valid_pool[@]}"; line="${valid_pool[$RND]}"
         if [ -n "$infence" ]; then GEN_WANT="$GEN_WANT quoted"; else GEN_WANT="$GEN_WANT ok"; GEN_OKS="$GEN_OKS$line$US"; fi ;;
      H) rnd "${#hostile_pool[@]}"; line="${hostile_pool[$RND]}"
         if [ -n "$infence" ]; then GEN_WANT="$GEN_WANT quoted"; else GEN_WANT="$GEN_WANT near-miss"; fi ;;
      N) rnd "${#noise_pool[@]}"; line="${noise_pool[$RND]}" ;;
      F)
        if [ -n "$infence" ]; then
          # close: the same character, at least as long
          f="$fence_close_char$fence_close_char$fence_close_char"
          rnd 3; while [ "$RND" -gt 0 ]; do f="$f$fence_close_char"; RND=$((RND - 1)); done
          while [ "${#f}" -lt "$fence_len" ]; do f="$f$fence_close_char"; done
          line="$f"; infence=""
        else
          rnd "${#fence_open[@]}"; f="${fence_open[$RND]}"; line="$f"
          fence_close_char="${f%"${f#?}"}"; fence_len=0
          case "$f" in '```text') fence_len=3 ;; *) fence_len="${#f}" ;; esac
          infence=1
        fi ;;
    esac
    GEN_BODY="$GEN_BODY$line$LF"
    k=$((k + 1))
  done
}
US=$'\037'
gen_bodies=(); gen_want=(); gen_oks=()
g=0
while [ "$g" -lt 150 ]; do
  gen_body
  gen_bodies+=("$GEN_BODY"); gen_want+=("${GEN_WANT# }"); gen_oks+=("$GEN_OKS")
  g=$((g + 1))
done
bundle="$(rh_join_bundle "${gen_bodies[@]}")"
for mode in $mode_list; do
  rh_bundle "S249/generator (seed 425)" "$mode" model-record "$bundle" || continue
  g=0
  while [ "$g" -lt "${#gen_bodies[@]}" ]; do
    got="$(rh_classes_for $((g + 1)))"
    if [ "$got" != "${gen_want[$g]}" ]; then
      fail "S249/generator (seed 425) [$mode] — body $((g + 1)) (reproduce: seed 425, the $((g + 1))th body): want '${gen_want[$g]}', got '$got'${LF}$(printf '%s' "${gen_bodies[$g]}" | LC_ALL=C head -c 600)"
    else
      # the ok rows are exactly the valid lines the generator placed outside fences, in order
      want_oks="${gen_oks[$g]}"
      got_oks=""
      j=1
      while txt="$(rh_text_for $((g + 1)) ok "$j")"; do
        got_oks="$got_oks$txt$US"
        j=$((j + 1))
      done
      [ "$got_oks" = "$want_oks" ] || fail "S249/generator (seed 425) [$mode] — body $((g + 1)): the ok lines are not the inserted valid records, in order"
    fi
    g=$((g + 1))
  done
done

# ============================================================================
# (d) scale: 60 bodies, a 100 KB value, a 100 KB hostile line
# ============================================================================
big="$(LC_ALL=C head -c 100000 /dev/zero | LC_ALL=C tr '\0' 'x')"
big_ok="<!-- model-record: stage=Review model=\"m1\" floor-basis=\"$big\" -->"
big_bad="<!-- model-record: stage=Review model=\"m1\" floor-basis=\"$big>\" -->"
sc=()
g=0
while [ "$g" -lt 60 ]; do
  case "$g" in
    20) sc+=("${big_ok}${LF}${valid_a}") ;;
    40) sc+=("${big_bad}${LF}${valid_a}") ;;
    *) sc+=("${valid_a}${LF}${valid_a}") ;;
  esac
  g=$((g + 1))
done
bundle="$(rh_join_bundle "${sc[@]}")"
for mode in $mode_list; do
  t0="$(date +%s)"
  rh_bundle "S249/scale" "$mode" model-record "$bundle" || continue
  t1="$(date +%s)"
  echo "    NOTE: S249 scale [$mode] — 60 bodies, one 100 KB value and one 100 KB hostile line: $((t1 - t0)) s (reported, not a failure)" >&2
  [ "$(rh_classes_for 21)" = "ok ok" ] && [ "$(rh_classes_for 41)" = "near-miss ok" ] && [ "$(rh_classes_for 1)" = "ok ok" ] \
    || fail "S249/scale [$mode] — wrong classes for bodies 1, 21, 41: '$(rh_classes_for 1)' '$(rh_classes_for 21)' '$(rh_classes_for 41)'"
  [ "$(rh_text_for 21 ok 1)" = "$big_ok" ] || fail "S249/scale [$mode] — the 100 KB ok line is not returned verbatim"
  i=0
  while [ "$i" -lt "$RH_N" ]; do
    if [ "${RH_CLS[$i]}" = near-miss ] && [ "${#RH_TXT[$i]}" -gt 400 ]; then
      fail "S249/scale [$mode] — a near-miss row holds ${#RH_TXT[$i]} bytes: a 100 KB line is cut, never dumped"
    fi
    i=$((i + 1))
  done
  [ "$RH_N" -eq 121 ] || fail "S249/scale [$mode] — want 121 rows, got $RH_N"
done

test_done
