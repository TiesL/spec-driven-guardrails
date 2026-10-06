#!/usr/bin/env bash
# S248 — the frozen corpus: every row of test/fixtures/marker-corpus.jsonl gets its labelled class and fields from rec_scan, alone and wrapped in a fence; the counts match the fixture header; the fixture is self-consistent and clean (K1)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC1; A35a "K1, the corpus fixture". Seam:
# rec_scan_bundle (one body per row: bulk), rec_scan (one body per row: a
# sample and every synthetic row), rec_field (every attribute of every ok row).
#
# What the fixture is. test/fixtures/marker-corpus.jsonl: a header object, then
# one object per row: row (id), kind (model-record or pipeline-override), line
# (or line_octal and octal:true for bytes JSON cannot hold), context (where the
# line came from, or "synthetic"), expected (ok, near-miss, quoted or text),
# stage and fields (ok rows), oracle, v030 (what the v0.3.0 pipeline made of
# the line alone), intended-shift, label-reason. 1290 corpus rows are every
# line of this public repo's issue and PR bodies, comments and review bodies
# (snapshot 2026-10-06) that contains `model-record` or `pipeline-override`;
# 74 synthetic rows (counted separately) cover what the corpus does not: one
# near-miss per A31a reason, `<` and `>` alone, `--` alone (ok), a CR in a
# value, NBSP and a zero-width space after `<!--` (text: a stated limit, pinned),
# `<!-- model-record-gate: x -->` (text), a value ending in ` floor-basis=`.
#
# The oracle (QA critique D8: a fixture whose oracle is the pattern under test
# can never go red). For every `ok` model-record row the oracle is the v0.3.0
# parser (marker_scan, marker_find, marker_attr of lib/model-record.sh at commit
# 411699d), run ONCE per row alone; stage, model and floor-basis agree with the
# labelled fields on every ok row (the fixture says so per row and this case
# checks the claim). It is never regenerated from the new code. Every other row
# is hand-labelled with a reason. `pipeline-override` had no library reader in
# v0.3.0 (the gate used a `[^>]*-->` regex), so those rows are hand-labelled.
# A grammar change that moves a row must name it: the header's
# `intended-shifts` list is exactly the rows whose v0.3.0 class differs from
# their v2 class (4+ space indent, inline, `>` or `<` or a control byte in a
# value, a missing model, ...); this case fails if the list and the rows
# disagree, and fails any row whose reader class differs from `expected`.
#
# What is NOT in the fixture: NUL (a bash argument cannot carry it); fence shapes
# beyond the wrap (S244 labels those against GitHub's renderer); and a row is a
# line replayed ALONE, so a line that sat inside a fence in its original comment
# is an ok row here (the header's phase-1a floor counts live records after fence
# stripping: 396 ok, 965 lines; this fixture is a superset, 1290 lines and more
# ok rows, and the counts are at least those floors).
#
# Threat model: ACCIDENTAL regressions of a grammar change against everything
# this repo has actually written (what real roles typed and the emitter
# produced), plus the pinned limits. Not a forger.
#
# Privacy: the fixture passes the repo's name check (the owner's first name is
# checked by SHA-256 only, as in S159, words of that name's length) and a secret
# scan (a pattern scan here; gitleaks too when it is installed). One corpus
# line carried the name and is withheld (header: rows-withheld).
#
# Red today: the fixture checks (section 1) are green on arrival and are the
# regression part of this scenario; the reader checks (sections 2 to 4) are red
# because the functions are stubs. Mutations this case must not survive (kill
# table): any grammar change that shifts a class (a loosened value byte class, a
# dropped column-0 rule, a missing near-miss branch, an unwrapped fence strip),
# `rec_field` returning a wrong model or floor-basis for the 61-odd legacy models
# with spaces, a reader that mislabels an indented or inline row.

# shellcheck disable=SC2034,SC2154,SC2329  # rd fills named variables; the k1_* functions run through rh_run
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
fixture="$TEST_REPO_ROOT/test/fixtures/marker-corpus.jsonl"
command -v jq >/dev/null 2>&1 || { fail "S248 — jq is needed to read the fixture"; test_done; }
[ -r "$fixture" ] || { fail "S248 — test/fixtures/marker-corpus.jsonl is missing"; test_done; }

jqh() { jq -r "select(.header == true) | $1" "$fixture"; }
jqr() { jq -r "select(.header != true) | $1" "$fixture"; }

# --- 1. the fixture itself (no reader needed; a regression scenario) ----------
hdr_oracle="$(jqh '.oracle["for-ok-rows"]')"
case "$hdr_oracle" in
  *411699d*) : ;;
  *) fail "S248/header — the header must record the oracle commit 411699d, got: '$hdr_oracle'" ;;
esac
for key in corpus-by-class synthetic-by-class all-by-class; do
  for cls in ok near-miss quoted text; do
    want="$(jqh ".counts[\"$key\"][\"$cls\"] // 0")"
    case "$key" in
      corpus-by-class) got="$(jqr 'select(.synthetic != true and .expected == "'"$cls"'") | 1' | LC_ALL=C grep -ac 1)" ;;
      synthetic-by-class) got="$(jqr 'select(.synthetic == true and .expected == "'"$cls"'") | 1' | LC_ALL=C grep -ac 1)" ;;
      all-by-class) got="$(jqr 'select(.expected == "'"$cls"'") | 1' | LC_ALL=C grep -ac 1)" ;;
    esac
    [ "$got" = "$want" ] || fail "S248/header counts — $key.$cls: the header says $want, the rows hold $got"
  done
done
got="$(jqr '1' | LC_ALL=C grep -ac 1)"
[ "$got" = "$(jqh '.counts["all-rows"]')" ] || fail "S248/header counts — all-rows says $(jqh '.counts["all-rows"]'), the file has $got rows"
[ "$(jqh '.counts["corpus-rows"]')" -ge "$(jqh '.["phase-1a-floor"]["lines-mentioning"]')" ] || fail "S248/floor — fewer corpus rows than the Phase 1a floor"
[ "$(jqh '.counts["corpus-by-class"].ok')" -ge "$(jqh '.["phase-1a-floor"]["live-strict-records"]')" ] || fail "S248/floor — fewer ok corpus rows than the Phase 1a floor"
[ "$(jqh '.counts["synthetic-rows"]')" -ge 70 ] || fail "S248/synthetic — fewer than 70 synthetic rows"
dups="$(jqr '.row' | LC_ALL=C sort | LC_ALL=C uniq -d | LC_ALL=C head -1)"
[ -z "$dups" ] || fail "S248/rows — a row id occurs twice: $dups"
bad="$(jqr 'select((.["label-reason"] // "") == "" or (.expected | IN("ok","near-miss","quoted","text") | not) or (.kind | IN("model-record","pipeline-override") | not)) | .row' | LC_ALL=C head -3)"
[ -z "$bad" ] || fail "S248/rows — a row without a label-reason, a valid class or a kind: $bad"
bad="$(jqr 'select(.expected == "ok" and .kind == "model-record" and ((.oracle // "") | startswith("v0.3.0 marker_scan+marker_attr agree") | not)) | .row' | LC_ALL=C head -3)"
[ -z "$bad" ] || fail "S248/oracle — an ok model-record row whose v0.3.0 oracle does not agree: $bad"
bad="$(jqr 'select(.expected == "ok" and (.stage == null or .fields == null)) | .row' | LC_ALL=C head -3)"
[ -z "$bad" ] || fail "S248/rows — an ok row without stage or fields: $bad"
listed="$(jqh '.["intended-shifts"] | sort | join(" ")')"
derived="$(jqr 'select(.v030 != null and .v030 != .expected) | .row' | LC_ALL=C sort | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed 's/ $//')"
[ "$listed" = "$derived" ] || fail "S248/intended shifts — the header list and the rows whose v0.3.0 class differs from their v2 class disagree:${RH_LF}list:    $listed${RH_LF}derived: $derived"
marked="$(jqr 'select(.["intended-shift"] != null) | .row' | LC_ALL=C sort | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed 's/ $//')"
[ "$marked" = "$derived" ] || fail "S248/intended shifts — the rows carrying an intended-shift note differ from the derived set"
[ "$(jqr 'select(.row == "s-t-nbsp-after-open" or .row == "s-t-zw-after-open") | select(.expected == "text") | 1' | LC_ALL=C grep -ac 1)" = 2 ] \
  || fail "S248/limits — the NBSP and zero-width rows (a stated limit) must be pinned as text"

# privacy: no personal name (SHA-256, words of the name's length only), no secret shapes
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | LC_ALL=C cut -d' ' -f1; else shasum -a 256 | LC_ALL=C cut -d' ' -f1; fi
}
forbidden='a8c8354a453539e374fa8f9a069cad803c280871e99ca2ab2ab46afb23a1acb9'
while IFS= read -r word; do
  [ -n "$word" ] || continue
  [ "$(printf '%s' "$word" | sha256)" != "$forbidden" ] || fail "S248/privacy — the fixture holds a name the repo forbids (a word of length ${#word}, by hash)"
done < <(LC_ALL=C tr -cs 'A-Za-z' '\n' <"$fixture" | LC_ALL=C awk 'length($0) == 4' | LC_ALL=C sort -u)
if LC_ALL=C grep -aEq 'gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{20,}\.eyJ' "$fixture"; then
  fail "S248/privacy — the fixture holds something that looks like a secret"
fi
if LC_ALL=C grep -aEq '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}' "$fixture"; then
  fail "S248/privacy — the fixture holds an email address"
fi
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-git --source "$fixture" --no-banner >/dev/null 2>&1 || fail "S248/privacy — gitleaks reports a leak in the fixture"
fi

rh_init "S248" || test_done

# --- 2. read the rows once ----------------------------------------------------
# One NUL-terminated stream per row: row, kind, expected, stage, octal, line,
# nfields, then name and value per field. The line of an octal row is a printf
# %b string (bytes JSON cannot hold), decoded here.
ROWS_ID=(); ROWS_KIND=(); ROWS_EXP=(); ROWS_STG=(); ROWS_LINE=(); ROWS_SYN=()
ROW_FIELDS=()   # per row: the fields as "name<US>value<US>name<US>value..." (US = U+001F, never in a value)
US=$'\037'
exec 3< <(jq -j 'select(.header != true) | [.row, .kind, .expected, (.stage // ""), (if .octal == true then "1" else "0" end), (if .octal == true then .line_octal else .line end), ((.synthetic == true) | tostring), ((.fields // {}) | length | tostring)] + ((.fields // {}) | to_entries | map(.key, .value)) | map(., "\u0000") | add' "$fixture")
rd() { IFS= read -r -d '' "$1" <&3; }
n=0
while rd id; do
  rd kind; rd exp; rd stg; rd oct; rd line; rd syn; rd nf
  fields=""
  k=0
  while [ "$k" -lt "$nf" ]; do
    rd fname; rd fval
    if [ "$oct" = 1 ]; then fval="$(printf '%b' "$fval")"; fi
    fields="$fields$fname$US$fval$US"
    k=$((k + 1))
  done
  if [ "$oct" = 1 ]; then line="$(printf '%b' "$line")"; fi
  ROWS_ID[n]="$id"; ROWS_KIND[n]="$kind"; ROWS_EXP[n]="$exp"; ROWS_STG[n]="$stg"; ROWS_LINE[n]="$line"; ROWS_SYN[n]="$syn"; ROW_FIELDS[n]="$fields"
  n=$((n + 1))
done
exec 3<&-
total="${#ROWS_ID[@]}"
[ "$total" -ge 1300 ] || fail "S248 — read only $total rows from the fixture"

# --- 3. classify: a bundle per kind (alone), the same wrapped; counts ------------
# Runs in one subshell per mode (the locale environment), printing one problem
# per line, so the loop costs one process per mode and not one per row.
k1_check() { # k1_check wrapped(0|1): prints problems, then COUNTS lines
  local wrapped="$1" kind i idx body bundle="" line fence rest run longest
  local -a map=()
  for kind in model-record pipeline-override; do
    bundle=""
    map=()
    i=0
    while [ "$i" -lt "$total" ]; do
      if [ "${ROWS_KIND[$i]}" = "$kind" ]; then
        line="${ROWS_LINE[$i]}"
        case "$line" in *"$RH_SEP"*) i=$((i + 1)); continue ;; esac   # U+001E rows run through rec_scan below
        if [ "$wrapped" = 1 ]; then
          longest=0
          rest="$line"
          while [ -n "$rest" ]; do
            case "$rest" in
              '`'*)
                run=0
                while [ "${rest#'`'}" != "$rest" ]; do rest="${rest#'`'}"; run=$((run + 1)); done
                [ "$run" -le "$longest" ] || longest="$run"
                ;;
              *) rest="${rest#?}" ;;
            esac
          done
          fence='```'
          while [ "${#fence}" -le "$longest" ]; do fence="$fence\`"; done
          body="$fence$RH_LF$line$RH_LF$fence"
        else
          body="$line"
        fi
        bundle="$bundle${body//$RH_SEP/}$RH_SEP"
        map+=("$i")
      fi
      i=$((i + 1))
    done
    out="$(rec_scan_bundle "$kind" "$bundle")" || { echo "FAIL rec_scan_bundle $kind (wrapped=$wrapped) exited $?"; continue; }
    # rows per body index
    local -a cls=() stg=() txt=() cnt=()
    local j=0
    while [ "$j" -lt "${#map[@]}" ]; do cls[j]=""; cnt[j]=0; j=$((j + 1)); done
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      idx="${row%%"$RH_TAB"*}"
      rest="${row#*"$RH_TAB"}"
      c="${rest%%"$RH_TAB"*}"
      rest="${rest#*"$RH_TAB"}"
      s="${rest%%"$RH_TAB"*}"
      t="${rest#*"$RH_TAB"}"
      j=$((idx - 1))
      if [ "$j" -lt 0 ] || [ "$j" -ge "${#map[@]}" ]; then echo "FAIL a row with body index $idx outside 1..${#map[@]}"; continue; fi
      cnt[j]=$((cnt[j] + 1))
      cls[j]="$c"; stg[j]="$s"; txt[j]="$t"
    done <<<"$out"
    j=0
    while [ "$j" -lt "${#map[@]}" ]; do
      i="${map[$j]}"
      want="${ROWS_EXP[$i]}"
      if [ "$wrapped" = 1 ] && [ "$want" != text ]; then want=quoted; fi
      if [ "$want" = text ]; then
        [ "${cnt[$j]}" -eq 0 ] || echo "FAIL ${ROWS_ID[$i]}: a non-candidate line gave ${cnt[$j]} row(s), first class '${cls[$j]}'"
      else
        if [ "${cnt[$j]}" -ne 1 ] || [ "${cls[$j]}" != "$want" ]; then
          echo "FAIL ${ROWS_ID[$i]}: want one '$want' row, got ${cnt[$j]} row(s), class '${cls[$j]}'"
        elif [ "$wrapped" = 0 ] && [ "$want" = ok ]; then
          [ "${txt[$j]}" = "${ROWS_LINE[$i]}" ] || echo "FAIL ${ROWS_ID[$i]}: the ok row's line differs from the row's line"
          if [ "${ROWS_KIND[$i]}" = model-record ] && [ "${stg[$j]}" != "${ROWS_STG[$i]}" ]; then
            echo "FAIL ${ROWS_ID[$i]}: stage '${stg[$j]}', want '${ROWS_STG[$i]}'"
          fi
        fi
      fi
      echo "COUNT ${ROWS_SYN[$i]} ${cls[$j]:-text}"
      j=$((j + 1))
    done
    unset cls stg txt cnt
  done
}

k1_fields() { # every attribute of every ok row, read through rec_field
  local i name val fields rest got nm seen
  i=0
  while [ "$i" -lt "$total" ]; do
    if [ "${ROWS_EXP[$i]}" = ok ]; then
      fields="${ROW_FIELDS[$i]}"
      seen=" "
      while [ -n "$fields" ]; do
        name="${fields%%"$US"*}"; rest="${fields#*"$US"}"
        val="${rest%%"$US"*}"; fields="${rest#*"$US"}"
        seen="$seen$name "
        got="$(rec_field "${ROWS_LINE[$i]}" "$name")" || { echo "FAIL ${ROWS_ID[$i]}: rec_field '$name' failed"; continue; }
        [ "$got" = "$val" ] || echo "FAIL ${ROWS_ID[$i]}: rec_field '$name' gave '$got', want '$val'"
      done
      for nm in floor-basis effort same-model-exception no-such-attribute; do
        case "$seen" in *" $nm "*) continue ;; esac
        got="$(rec_field "${ROWS_LINE[$i]}" "$nm")" || { echo "FAIL ${ROWS_ID[$i]}: rec_field '$nm' failed on an absent attribute"; continue; }
        [ -z "$got" ] || echo "FAIL ${ROWS_ID[$i]}: rec_field '$nm' gave '$got' for an attribute the row does not have"
      done
    fi
    i=$((i + 1))
  done
}

k1_single() { # rec_scan on one body per row: every 8th corpus row and every synthetic row
  local i got want c
  i=0
  while [ "$i" -lt "$total" ]; do
    if [ "${ROWS_SYN[$i]}" = true ] || [ $((i % 8)) -eq 0 ]; then
      got="$(rec_scan "${ROWS_KIND[$i]}" "${ROWS_LINE[$i]}")" || { echo "FAIL ${ROWS_ID[$i]}: rec_scan exited $?"; i=$((i + 1)); continue; }
      want="${ROWS_EXP[$i]}"
      if [ "$want" = text ]; then
        [ -z "$got" ] || echo "FAIL ${ROWS_ID[$i]}: rec_scan gave rows for a non-candidate line: $got"
      else
        c="${got#*"$RH_TAB"}"
        c="${c%%"$RH_TAB"*}"
        [ "$(printf '%s\n' "$got" | LC_ALL=C grep -ac .)" = 1 ] && [ "$c" = "$want" ] || echo "FAIL ${ROWS_ID[$i]}: rec_scan: want one '$want' row, got: $got"
      fi
    fi
    i=$((i + 1))
  done
}

emit_problems() { # <label> <mode>: RH_OUT lines starting with FAIL become failures
  local label="$1" mode="$2" row
  [ "$RH_RC" -eq 0 ] || fail "S248/$label [$mode] — the checker exited $RH_RC (stderr: '$RH_ERR')"
  while IFS= read -r row; do
    case "$row" in FAIL*) fail "S248/$label [$mode] — ${row#FAIL }" ;; esac
  done <<<"$RH_OUT"
}
count_of() { printf '%s\n' "$RH_OUT" | LC_ALL=C grep -ac "^COUNT $1 $2\$"; }

for mode in C LANG; do
  case " $RH_MODES " in *" $mode "*) : ;; *) continue ;; esac
  rh_run "$mode" k1_check 0
  emit_problems "alone" "$mode"
  # aggregate counts equal the header (corpus, synthetic, all)
  for cls in ok near-miss quoted text; do
    c_corpus="$(count_of false "$cls")"; c_syn="$(count_of true "$cls")"
    h_corpus="$(jqh ".counts[\"corpus-by-class\"][\"$cls\"] // 0")"; h_syn="$(jqh ".counts[\"synthetic-by-class\"][\"$cls\"] // 0")"
    # U+001E rows are not in the bundle; they are checked in k1_single and count as near-miss here
    [ "$cls" = near-miss ] && c_syn=$((c_syn + $(jqr 'select(.synthetic == true and (.line // "" | contains("\u001e"))) | 1' | LC_ALL=C grep -ac 1)))
    [ "$c_corpus" = "$h_corpus" ] || fail "S248/counts [$mode] — corpus $cls: the reader gives $c_corpus rows, the header says $h_corpus"
    [ "$c_syn" = "$h_syn" ] || fail "S248/counts [$mode] — synthetic $cls: the reader gives $c_syn rows, the header says $h_syn"
  done
  rh_run "$mode" k1_check 1
  emit_problems "wrapped" "$mode"
  # every wrapped candidate row is quoted: no ok and no near-miss row survives a fence
  for cls in ok near-miss; do
    [ "$(count_of false "$cls")" = 0 ] && [ "$(count_of true "$cls")" = 0 ] || fail "S248/wrapped [$mode] — a wrapped row came back '$cls'"
  done
  rh_run "$mode" k1_fields
  emit_problems "fields" "$mode"
  rh_run "$mode" k1_single
  emit_problems "single" "$mode"
done

test_done
