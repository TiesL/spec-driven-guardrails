#!/usr/bin/env bash
# S230 — live_text reads a body holding an invalid or truncated UTF-8 sequence the same under a UTF-8 LANG as under LC_ALL=C, in the library and in all three callers.
# Covers: F34, F35, F39
#
# Issue #423 AC2 (slice V2 of #411; A32a, A35a D3). On BWK awk (macOS) a
# regex test on a body holding `\377` or a truncated `\342\200` aborts with
# "towc: multibyte conversion failure" unless the awk call carries the
# per-command `LC_ALL=C` prefix (a `local LC_ALL=C` in a function is not
# enough when LC_ALL was never exported, A32a). Gawk and mawk do not abort,
# so the case that proves the prefix is the macOS leg; this file is written
# to bite there (case-level LC_ALL unset, LANG=en_US.UTF-8).
#
# Seams: lib/markdown.sh (md_strip_fences, live_text) called in a fresh bash;
# model-record-gate.sh stdout (its main path, and its role-play path, which
# today calls live_text without the C locale: the #406 item); the
# collector's rows 1-3 (compliance-evidence.sh); role-label-staleness.sh's
# verdict line. Gate and callers run against fake gh. The bytes reach the
# gate through a placeholder (@FF@, @TR@) swapped for raw bytes after jq, since
# jq itself would turn an invalid byte into U+FFFD.
#
# Regression arms (green on arrival, labelled R): the lib arms are red only
# while lib/markdown.sh is a stub; the gate main path already carries the
# prefix; the valid-multibyte control and the C-locale reads are green today.
# Red today on a macOS host: the role-play arm, the collector arm and the
# staleness arm (their live_text copies run without the prefix).
# MD_LIB points the lib arms at a scratch copy (mutation proof).
#
# Review round 1 of PR #443 (finding c-locale-grep-callers, lib-normalize-locale):
# the C locale must also hold for the callers' OWN grep (and tr) on the live
# text. BSD grep 2.6.0 in a UTF-8 locale finds NO match on a line where an
# invalid byte comes BEFORE the match, so a marker after `x\377y ` on its line is
# lost. Every arm labelled "before" below puts the bytes BEFORE the marker on
# the same line, in every body source that has its own tr or grep site (the
# existing arms put them after the start of the marker, which BSD grep still
# matches). Mutation: remove `LC_ALL=C` from one caller grep or tr at a time;
# each removal must turn a "before" arm red (equivalent mutants, not
# killable: a grep or sed whose input is already the -o output of a
# C-locale grep, so it holds only ASCII).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/markdown-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/markdown-helpers.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S230 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
md_need_locale "S230" || test_done

NL=$'\n'

# --- the three byte classes, as (name, placeholder, bytes) -------------------
# valid multibyte is the green control: it must read the same in every arm.
byte_names="invalid truncated valid-multibyte"
bytes_of() {
  case "$1" in
    invalid) printf '%s' "$MD_FF" ;;
    truncated) printf '%s' "$MD_TRUNC" ;;
    valid-multibyte) printf '%s' "$MD_EMDASH" ;;
  esac
}
placeholder_of() {
  case "$1" in
    invalid) printf '@FF@' ;;
    truncated) printf '@TR@' ;;
    valid-multibyte) printf '@MB@' ;;
  esac
}

# =========================================================================
# 1. library: live_text and md_strip_fences, LC_ALL unset + LANG utf8 vs C
# =========================================================================
lib_case() { # label name body fn expect-in-C... (needles that must be in the C output)
  local label="$1" fn="$2" body="$3" out_c rc_c needle
  shift 3
  md_run_lib C "$fn" "$body"
  out_c="$MD_OUT"
  rc_c="$MD_RC"
  if [ "$rc_c" -ne 0 ]; then
    fail "S230 lib/$label — $fn exit $rc_c under LC_ALL=C (a stub, or a broken program)"
    return
  fi
  for needle in "$@"; do
    md_has "$out_c" "$needle" || fail "S230 lib/$label — $fn under LC_ALL=C lost '$needle' (vacuous or wrong baseline): $(printf '%q' "$out_c")"
  done
  md_run_lib utf8 "$fn" "$body"
  [ "$MD_RC" -eq 0 ] || fail "S230 lib/$label — $fn exit $MD_RC with LC_ALL unset and LANG=$MD_UTF8 (awk aborted on the bytes?)"
  [ "$MD_OUT" = "$out_c" ] || fail "S230 lib/$label — $fn reads this body differently under LANG=$MD_UTF8 than under LC_ALL=C: $(printf '%q' "$MD_OUT") vs $(printf '%q' "$out_c")"
}
for name in $byte_names; do
  b="$(bytes_of "$name")"
  marker="<!-- model-record: stage=Test model=\"x${b}y\" -->"
  after='<!-- model-record: stage=Review model="AFTERFENCE" -->'
  # the bad bytes inside a live marker line
  lib_case "$name/live line" live_text "before${NL}${marker}${NL}after" "stage=Test" "x${b}y"
  lib_case "$name/live line" md_strip_fences "before${NL}${marker}${NL}after" "stage=Test" "x${b}y"
  # the bad bytes inside a fence: blanked, and the marker after the fence stays live
  lib_case "$name/in fence" live_text "\`\`\`${NL}${marker}${NL}\`\`\`${NL}${after}" "AFTERFENCE"
  lib_case "$name/in fence" md_strip_fences "\`\`\`${NL}${marker}${NL}\`\`\`${NL}${after}" "AFTERFENCE"
  # the bad bytes in a code span and in a blockquote
  lib_case "$name/code span" live_text "see \`x${b}y\` and ${after}" "AFTERFENCE"
  lib_case "$name/blockquote" live_text "> quoted x${b}y${NL}${after}" "AFTERFENCE"
done
# the fenced bytes must not survive, in either locale (the fence is read, not skipped)
md_run_lib utf8 live_text "\`\`\`${NL}hidden${MD_FF}inside${NL}\`\`\`${NL}shown"
md_has "$MD_OUT" "hidden" && fail "S230 lib/fence — a fenced line holding \\377 must be blanked under LANG=$MD_UTF8, got: $(printf '%q' "$MD_OUT")"
md_has "$MD_OUT" "shown" || fail "S230 lib/fence — the line after the fence must stay under LANG=$MD_UTF8, got: $(printf '%q' "$MD_OUT")"

# --- normalize_model (lib/model-record.sh): tr and sed carry LC_ALL=C too ----
# lib-normalize-locale (round 1 of PR #443): every external command in lib/
# carries the per-command prefix. A model value holding an invalid byte must
# normalize to the same string under a UTF-8 LANG as under LC_ALL=C, with
# nothing on stderr (BSD tr aborts with "Illegal byte sequence" and cuts the
# value at the byte).
mr_lib="${MR_LIB:-$TEST_REPO_ROOT/lib/model-record.sh}"
for name in $byte_names; do
  b="$(bytes_of "$name")"
  # shellcheck disable=SC2016  # the program text is meant to expand in the child
  env LC_ALL=C bash -c '. "$1"; normalize_model "$2"' _ "$mr_lib" "claude-opus-5${b}" > "$SANDBOX/nm.c.out" 2> "$SANDBOX/nm.c.err"
  nm_c="$(cat "$SANDBOX/nm.c.out")"
  [ "$nm_c" = "opus 5" ] || fail "S230 lib/normalize_model/$name — baseline under LC_ALL=C should be 'opus 5', got $(printf '%q' "$nm_c") (a broken baseline)"
  # shellcheck disable=SC2016
  env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" bash -c '. "$1"; normalize_model "$2"' _ "$mr_lib" "claude-opus-5${b}" > "$SANDBOX/nm.u.out" 2> "$SANDBOX/nm.u.err"
  nm_u="$(cat "$SANDBOX/nm.u.out")"
  [ "$nm_u" = "$nm_c" ] || fail "S230 lib/normalize_model/$name — under LANG=$MD_UTF8 the model normalizes to $(printf '%q' "$nm_u"), under LC_ALL=C to $(printf '%q' "$nm_c")"
  [ ! -s "$SANDBOX/nm.u.err" ] || fail "S230 lib/normalize_model/$name — stderr under LANG=$MD_UTF8 is not empty: $(LC_ALL=C head -c 200 "$SANDBOX/nm.u.err")"
done

# normalize-sed1-untested (round 2 of PR #443): QA's earlier "equivalent" call
# for the FIRST sed of normalize_model was wrong. BSD sed aborts with "RE error:
# illegal byte sequence" whenever the anchored match (^[[:space:]]*claude)
# fails before it reaches the byte, so a value that does NOT start with
# "claude" is the one that bites; "claude-opus-5<bytes>" above never does.
# Values: no claude prefix, the bytes first, the bytes inside the word. Each
# must normalize to the same non-empty string under both locales with nothing
# on stderr. (R: green on arrival, the prefix is there; the scratch mutant
# `sed -E 's/^[[:space:]]*claude...` without it, via MR_LIB, is red.)
for name in $byte_names; do
  b="$(bytes_of "$name")"
  for val in "opus-5${b}" "${b}claude-opus-5" "claude${b}-opus" "x${b}"; do
    # shellcheck disable=SC2016
    env LC_ALL=C bash -c '. "$1"; normalize_model "$2"' _ "$mr_lib" "$val" > "$SANDBOX/nm.c.out" 2> "$SANDBOX/nm.c.err"
    nm_c="$(cat "$SANDBOX/nm.c.out")"
    [ -n "$nm_c" ] || fail "S230 lib/normalize_model-noclaude/$name/$(printf '%q' "$val") — baseline under LC_ALL=C is empty (a broken baseline)"
    # shellcheck disable=SC2016
    env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" bash -c '. "$1"; normalize_model "$2"' _ "$mr_lib" "$val" > "$SANDBOX/nm.u.out" 2> "$SANDBOX/nm.u.err"
    nm_u="$(cat "$SANDBOX/nm.u.out")"
    [ "$nm_u" = "$nm_c" ] || fail "S230 lib/normalize_model-noclaude/$name/$(printf '%q' "$val") — under LANG=$MD_UTF8 it normalizes to $(printf '%q' "$nm_u"), under LC_ALL=C to $(printf '%q' "$nm_c") (a sed ran without the C locale)"
    [ ! -s "$SANDBOX/nm.u.err" ] || fail "S230 lib/normalize_model-noclaude/$name/$(printf '%q' "$val") — stderr under LANG=$MD_UTF8 is not empty: $(LC_ALL=C head -c 200 "$SANDBOX/nm.u.err")"
  done
done

# --- effort_rank (lib/model-record.sh:57), lib-normalize-locale round 2 -------
# `effort_rank "low<bytes>"` prints nothing under LC_ALL=C (not a known
# effort). Under a UTF-8 LANG an unprefixed BSD `tr` cuts the value at the byte
# ("Illegal byte sequence" on stderr) and the rest reads as `low`: rank 0, a
# false "Review recorded lower effort" finding. RED today on a macOS host.
# Control: a plain `HIGH` ranks 2 (so the function is not a stub).
# shellcheck disable=SC2016
env LC_ALL=C bash -c '. "$1"; effort_rank "$2"' _ "$mr_lib" "HIGH" > "$SANDBOX/er.out" 2>&1
[ "$(cat "$SANDBOX/er.out")" = "2" ] || fail "S230 lib/effort_rank — control: HIGH should rank 2 under LC_ALL=C, got $(printf '%q' "$(cat "$SANDBOX/er.out")")"
for name in $byte_names; do
  b="$(bytes_of "$name")"
  # shellcheck disable=SC2016
  env LC_ALL=C bash -c '. "$1"; effort_rank "$2"' _ "$mr_lib" "low${b}" > "$SANDBOX/er.c.out" 2> "$SANDBOX/er.c.err"
  er_c="$(cat "$SANDBOX/er.c.out")"
  [ -z "$er_c" ] || fail "S230 lib/effort_rank/$name — baseline under LC_ALL=C: low+bytes is not a known effort and must rank as nothing, got $(printf '%q' "$er_c")"
  # shellcheck disable=SC2016
  env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" bash -c '. "$1"; effort_rank "$2"' _ "$mr_lib" "low${b}" > "$SANDBOX/er.u.out" 2> "$SANDBOX/er.u.err"
  er_u="$(cat "$SANDBOX/er.u.out")"
  [ "$er_u" = "$er_c" ] || fail "S230 lib/effort_rank/$name — under LANG=$MD_UTF8 'low'+bytes ranks as $(printf '%q' "$er_u"), under LC_ALL=C as nothing (tr cut the value at the byte)"
  [ ! -s "$SANDBOX/er.u.err" ] || fail "S230 lib/effort_rank/$name — stderr under LANG=$MD_UTF8 is not empty: $(LC_ALL=C head -c 200 "$SANDBOX/er.u.err")"
done

# =========================================================================
# 2. gate: main path and role-play path
# =========================================================================
script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$script" ] || { fail "S230 — model-record-gate.sh is missing or not executable"; test_done; }

id="process-multi-agent-roles"
gh_inner="$(fake_gh_rest "$SANDBOX/ghdata")"
export FAKE_GH_DATA="$SANDBOX/ghdata"
mkdir -p "$FAKE_GH_DATA"
# gh wrapper: the inner fake's output with the placeholders swapped for raw bytes
rawbin="$SANDBOX/rawgh"
mkdir -p "$rawbin"
cat > "$rawbin/gh" <<GHEOF
#!/bin/bash
tmp="\$(mktemp)"
trap 'rm -f "\$tmp"' EXIT
"$gh_inner/gh" "\$@" > "\$tmp" || exit \$?
ff="\$(printf '\\377')"
tr_="\$(printf '\\342\\200')"
mb="\$(printf '\\342\\200\\224')"
LC_ALL=C sed -e "s/@FF@/\$ff/g" -e "s/@TR@/\$tr_/g" -e "s/@MB@/\$mb/g" "\$tmp"
GHEOF
chmod +x "$rawbin/gh"

optin="$(fresh_project optin)"
write_adoption "$optin/WORKFLOW-ADOPTION.md" "$id" yes

GATE_OUT=""
GATE_RC=0
gate_run() { # mode (C|utf8)
  case "$1" in
    C) GATE_OUT="$(cd "$optin" && env LC_ALL=C PATH="$rawbin:$PATH" "$script" 246 2>/dev/null)" ;;
    utf8) GATE_OUT="$(cd "$optin" && env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" PATH="$rawbin:$PATH" "$script" 246 2>/dev/null)" ;;
  esac
  GATE_RC=$?
}
rec() { # stage model [extra attrs]
  printf '<!-- model-record: stage=%s model="%s" effort="high"%s -->' "$1" "$2" "${3:+ $3}"
}

for name in $byte_names; do
  ph="$(placeholder_of "$name")"
  # (main path) every stage in its own body; the Review record carries the
  # bytes in its free-text floor-basis. R: the main path has the prefix today.
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "$(rec Review opus "floor-basis=\"stronger x${ph}y\"")"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(rec Discovery sonnet)"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(rec Planning sonnet)" "$(rec Test sonnet)" "$(rec Implementation sonnet)"
  gate_run C
  c_out="$GATE_OUT"
  [ "$GATE_RC" -eq 0 ] || fail "S230 gate main/$name — exit $GATE_RC under LC_ALL=C"
  md_has "$c_out" "model-record:" && fail "S230 gate main/$name — a complete, well-formed run must print no model-record: finding under LC_ALL=C (broken baseline), got: $c_out"
  # the baseline must be able to say something: drop the Review record and the gate names it
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  gate_run C
  md_has "$GATE_OUT" "no record found for stage Review" || fail "S230 gate main/$name — control: without the Review record the gate must name the missing stage, got: $GATE_OUT"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "$(rec Review opus "floor-basis=\"stronger x${ph}y\"")"
  gate_run utf8
  [ "$GATE_RC" -eq 0 ] || fail "S230 gate main/$name — exit $GATE_RC with LC_ALL unset and LANG=$MD_UTF8"
  [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate main/$name — output differs under LANG=$MD_UTF8 from LC_ALL=C: '$GATE_OUT' vs '$c_out'"

  # (role-play path) two stages in one comment body, one carrying the bytes:
  # the finding "stages in one text" must be printed exactly as under C.
  # Red today on a macOS host: check_text runs live_text without the prefix.
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(rec Discovery sonnet)"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(rec Planning sonnet)" "$(rec Test sonnet)" "$(rec Implementation sonnet)${NL}$(rec Review opus "floor-basis=\"stronger x${ph}y\"")"
  gate_run C
  c_out="$GATE_OUT"
  md_has "$c_out" "role-played: stages in one text: Implementation, Review" || fail "S230 gate role-play/$name — baseline under LC_ALL=C must report the two stages in one text, got: $c_out"
  gate_run utf8
  [ "$GATE_RC" -eq 0 ] || fail "S230 gate role-play/$name — exit $GATE_RC with LC_ALL unset and LANG=$MD_UTF8"
  [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate role-play/$name — the role-play check reads this body differently under LANG=$MD_UTF8 than under LC_ALL=C: '$GATE_OUT' vs '$c_out'"
done

# --- gate: the bytes BEFORE the marker on the same line (round 1 of PR #443) --
# The callers' own greps (main path stage check, role-play stage_ere, the
# override reader, the "stages missing" check) read the live text. Every
# body below puts `x<bytes>y ` before each marker on its line.
for name in $byte_names; do
  ph="$(placeholder_of "$name")"
  pre="x${ph}y "
  # (main path + stages missing) all five stages, each marker after the bytes
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "${pre}$(rec Review opus "floor-basis=\"stronger\"")"
  json_comments "$FAKE_GH_DATA/comments-239.json" "${pre}$(rec Discovery sonnet)"
  json_comments "$FAKE_GH_DATA/comments-246.json" "${pre}$(rec Planning sonnet)" "${pre}$(rec Test sonnet)" "${pre}$(rec Implementation sonnet)"
  gate_run C
  c_out="$GATE_OUT"
  [ -z "$c_out" ] || fail "S230 gate main-before/$name — baseline under LC_ALL=C: five records after the bytes must give no finding at all, got: $c_out"
  gate_run utf8
  [ "$GATE_RC" -eq 0 ] || fail "S230 gate main-before/$name — exit $GATE_RC with LC_ALL unset and LANG=$MD_UTF8"
  [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate main-before/$name — a marker after '$name' bytes on its line is read differently under LANG=$MD_UTF8 than under LC_ALL=C (a grep of the live text ran without the C locale): '$GATE_OUT' vs '$c_out'"

  # (role-play path) two stage records in one body: on separate lines, and on one line
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  json_comments "$FAKE_GH_DATA/comments-246.json" "${pre}$(rec Planning sonnet)" "${pre}$(rec Test sonnet)" "${pre}$(rec Implementation sonnet)${NL}${pre}$(rec Review opus "floor-basis=\"stronger\"")"
  gate_run C
  c_out="$GATE_OUT"
  md_has "$c_out" "role-played: stages in one text: Implementation, Review" || fail "S230 gate role-play-before/$name — baseline under LC_ALL=C must report the two stages in one text, got: $c_out"
  gate_run utf8
  [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate role-play-before/$name — separate lines: the role-play check reads this body differently under LANG=$MD_UTF8 than under LC_ALL=C: '$GATE_OUT' vs '$c_out'"
  json_comments "$FAKE_GH_DATA/comments-246.json" "${pre}$(rec Planning sonnet)" "${pre}$(rec Test sonnet)" "${pre}$(rec Implementation sonnet) $(rec Review opus "floor-basis=\"stronger\"")"
  gate_run C
  c_out="$GATE_OUT"
  md_has "$c_out" "role-played: stages in one text: Implementation, Review" || fail "S230 gate role-play-before/$name — one line: baseline under LC_ALL=C must report the two stages in one text, got: $c_out"
  gate_run utf8
  [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate role-play-before/$name — one line: the role-play check reads this body differently under LANG=$MD_UTF8 than under LC_ALL=C: '$GATE_OUT' vs '$c_out'"

  # (override reader) a single-session override waives the missing stages;
  # variant 1: the bytes before the marker; variant 2: before each attribute
  # inside it (the three attribute greps each read after a byte)
  ov_a="${pre}<!-- pipeline-override: decided-by=\"d\" reason=\"r\" scope=\"single-session\" -->"
  ov_b="<!-- pipeline-override: note=\"x${ph}y\" decided-by=\"d\" reason=\"r\" scope=\"single-session\" -->"
  ov_c="<!-- pipeline-override: decided-by=\"x${ph}y\" reason=\"x${ph}y\" scope=\"single-session\" -->"
  ov_n=0
  for ov in "$ov_a" "$ov_b" "$ov_c"; do
    ov_n=$((ov_n + 1))
    rm -f "${FAKE_GH_DATA:?}"/*.json
    json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
    json_comments "$FAKE_GH_DATA/reviews-246.json"
    json_comments "$FAKE_GH_DATA/comments-239.json"
    json_comments "$FAKE_GH_DATA/comments-246.json" "$ov"
    gate_run C
    c_out="$GATE_OUT"
    md_has "$c_out" "a pipeline-override (scope=single-session) is recorded" || fail "S230 gate override-before/$name/$ov_n — baseline under LC_ALL=C must read the single-session override, got: $c_out"
    gate_run utf8
    [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate override-before/$name/$ov_n — the override is read differently under LANG=$MD_UTF8 than under LC_ALL=C: '$GATE_OUT' vs '$c_out'"
  done
done

# --- gate: the closing keyword in the RAW title and description (line 161) ---
# Round 2 of PR #443 (c-locale-grep-callers, medium): the gate finds the
# closing issues with a grep over the raw PR title and description. BSD grep in
# a UTF-8 locale finds nothing on a line where an invalid byte comes BEFORE
# `Closes #239`; the issue is then never read, and the gate prints a false
# `no record found for stage Discovery` and the blocking `role-played: stages
# missing: Discovery`. Discovery is recorded on #239 only, the other four
# stages on the PR; under LC_ALL=C the gate prints nothing. RED today on a
# macOS host. After A32c the script's own `export LC_ALL=C` fixes it; the arm
# is red again if that line is removed.
for name in $byte_names; do
  ph="$(placeholder_of "$name")"
  for where in description title; do
    case "$where" in
      description) kw_title="Fix: something"; kw_desc="x${ph}y Closes #239" ;;
      title) kw_title="x${ph}y Closes #239: something"; kw_desc="no keyword in the description" ;;
    esac
    rm -f "${FAKE_GH_DATA:?}"/*.json
    json_pr "$FAKE_GH_DATA/pr-246.json" "$kw_title" "$kw_desc"
    json_comments "$FAKE_GH_DATA/reviews-246.json" "$(rec Review opus "floor-basis=\"stronger\"")"
    json_comments "$FAKE_GH_DATA/comments-239.json" "$(rec Discovery sonnet)"
    json_comments "$FAKE_GH_DATA/comments-246.json" "$(rec Planning sonnet)" "$(rec Test sonnet)" "$(rec Implementation sonnet)"
    gate_run C
    c_out="$GATE_OUT"
    [ -z "$c_out" ] || fail "S230 gate keyword-$where/$name — baseline under LC_ALL=C: the keyword after the bytes must still find #239 and give no finding, got: $c_out"
    # control: without the Discovery record on #239 the gate must say so (proves #239 is read)
    json_comments "$FAKE_GH_DATA/comments-239.json"
    gate_run C
    md_has "$GATE_OUT" "no record found for stage Discovery" || fail "S230 gate keyword-$where/$name — control under LC_ALL=C: without the Discovery record on #239 the gate must name the missing stage, got: $GATE_OUT"
    json_comments "$FAKE_GH_DATA/comments-239.json" "$(rec Discovery sonnet)"
    gate_run utf8
    [ "$GATE_RC" -eq 0 ] || fail "S230 gate keyword-$where/$name — exit $GATE_RC with LC_ALL unset and LANG=$MD_UTF8"
    [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate keyword-$where/$name — the closing keyword in the raw PR $where is read differently under LANG=$MD_UTF8 than under LC_ALL=C (the grep over the raw text ran without the C locale): '$GATE_OUT' vs '$c_out'"
  done
done

# --- gate: effort_rank on the Review record (round 2, lib-normalize-locale) ---
# The Reviewer's reproduction: Implementation `opus`/`high`, Review `opus`/`low<bytes>`.
# Under LC_ALL=C `low<bytes>` is not a known effort and the gate prints nothing;
# an unprefixed BSD tr turns it into `low` and the gate prints a false
# "Review recorded lower effort" finding.
for name in $byte_names; do
  ph="$(placeholder_of "$name")"
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "<!-- model-record: stage=Review model=\"opus\" effort=\"low${ph}\" floor-basis=\"ok\" -->"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(rec Discovery sonnet)"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(rec Planning sonnet)" "$(rec Test sonnet)" "$(rec Implementation opus)"
  gate_run C
  c_out="$GATE_OUT"
  md_has "$c_out" "recorded lower effort" && fail "S230 gate effort/$name — baseline under LC_ALL=C: low+bytes is not a known effort, so no lower-effort finding is expected, got: $c_out"
  gate_run utf8
  [ "$GATE_OUT" = "$c_out" ] || fail "S230 gate effort/$name — the Review effort low+bytes is read differently under LANG=$MD_UTF8 than under LC_ALL=C (effort_rank's tr ran without the C locale): '$GATE_OUT' vs '$c_out'"
done

# =========================================================================
# 3. collector: gate rows 1-3
# =========================================================================
# shellcheck source=../compliance-evidence-fixture.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"
ce_script="$TEST_REPO_ROOT/compliance-evidence.sh"
script="$ce_script"
export CE_ID=S230

# The comparison is the collector's FULL stdout (the evidence column of every
# row included) and its stderr, byte for byte, between the two locales
# (round 2 of PR #443, collector-cell-locale: `cell()` ran sed/tr/cut in the
# ambient locale, so BSD sed aborted on the byte and the evidence cell came out
# empty). No status-only workaround: the baseline's statuses are read with a
# pinned sed, but the compared text is everything.
ce_run_to() { # mode outfile errfile: runs the collector on the last-built fake gh
  local mode="$1" bin
  bin="$(cat "$FAKEGH_OUT")"
  case "$mode" in
    C) env LC_ALL=C PATH="$bin:$PATH" "$ce_script" 279 > "$2" 2> "$3" ;;
    utf8) env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" PATH="$bin:$PATH" "$ce_script" 279 > "$2" 2> "$3" ;;
  esac
}
ce_status_of() { # file n: the status column of gate row n, pinned to the C locale
  LC_ALL=C sed -n "$(($2 + 2))p" "$1" | LC_ALL=C sed -E 's/^\| .* \| ([a-z-]+) \| .* \|$/\1/'
}
ce_compare() { # label: C and utf8 output of the last-built fake gh must be identical
  local label="$1"
  ce_run_to C "$SANDBOX/ce.c.out" "$SANDBOX/ce.c.err"
  ce_run_to utf8 "$SANDBOX/ce.u.out" "$SANDBOX/ce.u.err"
  cmp -s "$SANDBOX/ce.c.out" "$SANDBOX/ce.u.out" || fail "S230 $label — the collector's full output (evidence text included) differs under LANG=$MD_UTF8 from LC_ALL=C: $(LC_ALL=C diff "$SANDBOX/ce.c.out" "$SANDBOX/ce.u.out" | LC_ALL=C head -c 600 | LC_ALL=C tr '\n' ' ')"
  cmp -s "$SANDBOX/ce.c.err" "$SANDBOX/ce.u.err" || fail "S230 $label — the collector's stderr differs under LANG=$MD_UTF8 from LC_ALL=C: $(LC_ALL=C head -c 300 "$SANDBOX/ce.u.err")"
}
for name in $byte_names; do
  b="$(bytes_of "$name")"
  # all four stages are recorded across the PR comment and the issue; the
  # Test record carries the bytes. The Review record and the done marker keep
  # rows 2 and 3 real, so a body read as empty would change them too.
  ce "Closes #265" "$(mk Planning claude-sonnet-5 medium)
$(mk Test "claude-sonnet-5${b}" medium)
$(mk Implementation claude-sonnet-5 medium)
$(mk Review claude-sonnet-5 medium "$FB")
<!-- pre-merge-review:done sha=$SHA -->" "$(mk Discovery claude-sonnet-5 low)" >/dev/null 2>&1
  ce_run_to C "$SANDBOX/ce.c.out" "$SANDBOX/ce.c.err"
  c_rows="$(ce_status_of "$SANDBOX/ce.c.out" 1)/$(ce_status_of "$SANDBOX/ce.c.out" 2)/$(ce_status_of "$SANDBOX/ce.c.out" 3)"
  [ "$c_rows" = "evidenced/evidenced/evidenced" ] || fail "S230 collector/$name — baseline under LC_ALL=C: rows 1-3 should be evidenced/evidenced/evidenced, got $c_rows (a broken fixture)"
  ce_compare "collector/$name"
done

# --- collector: issue-side efforts holding a byte (compliance-evidence.sh:622) -
# Two closing issues each record a Review marker. The collector lower-cases
# each issue-side effort with `tr` and calls the two issues in conflict when
# they differ. BSD tr cuts `low<bytes>` to `low` under a UTF-8 LANG, so against
# an issue that says plain `low` the conflict check sees agreement where
# LC_ALL=C sees a conflict (the evidence then also shows a cut value). Pairs:
# `low<bytes>` vs `low` (the verdict flips) and vs `high` (the conflict stays,
# the effort text printed in the evidence differs). RED today on a macOS host.
two="Closes #265, closes #266"
for name in $byte_names; do
  b="$(bytes_of "$name")"
  for other in low high; do
    ce "$two" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Review claude-sonnet-5 "low${b}" 'floor-basis="x"')" "$(mk Review claude-sonnet-5 "$other" 'floor-basis="x"')" >/dev/null 2>&1
    ce_run_to C "$SANDBOX/ce.c.out" "$SANDBOX/ce.c.err"
    [ "$(ce_status_of "$SANDBOX/ce.c.out" 2)" = "indeterminate" ] || fail "S230 collector-effort/$name/$other — baseline under LC_ALL=C: 'low'+bytes against '$other' is an effort conflict (row 2 indeterminate), got '$(ce_status_of "$SANDBOX/ce.c.out" 2)' (a broken fixture)"
    ce_compare "collector-effort/$name/$other"
  done
done

# --- collector: the bytes BEFORE the marker, in every body source ------------
# One record per reading site (as S231 does), each after `x<bytes>y ` on its
# line: the closing keyword in the PR title (its own tr site and the
# closing-keyword grep), Planning and the done marker in the PR body (own tr
# site), Test and Review in PR comments and Implementation in a PR review
# (the shared comment/review tr site), Discovery in the closing issue's
# comment (own tr site). The stage grep, the done-marker greps and the
# quoted-suffix grep each read after a byte.
ce_rows_full() { # mode: rows 1-3, status and evidence, of the last-built fake gh
  local mode="$1" bin out
  bin="$(cat "$FAKEGH_OUT")"
  case "$mode" in
    C) out="$(env LC_ALL=C PATH="$bin:$PATH" "$ce_script" 279 2>/dev/null)" ;;
    utf8) out="$(env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" PATH="$bin:$PATH" "$ce_script" 279 2>/dev/null)" ;;
  esac
  printf '%s\n' "$out" | LC_ALL=C sed -n '3,5p'
}
ce_before() { # <title> <body> <pr comments> <pr review> <issue comment>
  local title="$1" body="$2" prc="$3" prr="$4" ic="$5"
  body="${body//$'\n'/$'\001'}"
  {
    echo 'case "$*" in'
    echo '  __CALL_A__)'
    printf "    printf 'HEAD\\\\t%s\\\\n'\n" "$SHA"
    printf "    printf 'STATE\\\\tOPEN\\\\n'\n"
    printf "    printf 'TITLE\\\\t%%s\\\\n' '%s'\n" "$title"
    printf "    printf 'TEXT\\\\t%%s\\\\n' '%s'\n" "$body"
    echo '    exit 0 ;;'
    echo '  __CALL_A_COMMENTS__)'
    emit "$prc"
    echo '  __CALL_A_REVIEWS__)'
    emit "$prr"
    echo '  __CALL_B__)'
    printf "    printf 'check\\\\tSUCCESS\\\\tpass\\\\n'\n"
    echo '    exit 0 ;;'
    echo '  __CALL_C265__)'
    emit "$ic"
    echo 'esac'
    echo 'exit 1'
  } | run_build_fake_gh "$SHA"
}
for name in $byte_names; do
  b="$(bytes_of "$name")"
  pre="x${b}y "
  ce_before "${pre}Closes #265" \
    "${pre}$(mk Planning claude-sonnet-5 medium)${MD_LF}${pre}<!-- pre-merge-review:done sha=$SHA -->" \
    "${pre}$(mk Test claude-sonnet-5 medium)
${pre}$(mk Review claude-sonnet-5 medium "$FB")" \
    "${pre}$(mk Implementation claude-sonnet-5 medium)" \
    "${pre}$(mk Discovery claude-sonnet-5 low)"
  c_full="$(ce_rows_full C)"
  c_stat="$(printf '%s\n' "$c_full" | LC_ALL=C sed -E 's/^\| .* \| ([a-z-]+) \| .* \|$/\1/' | paste -sd/ -)"
  [ "$c_stat" = "evidenced/evidenced/evidenced" ] || fail "S230 collector-before/$name — baseline under LC_ALL=C: rows 1-3 should be evidenced/evidenced/evidenced, got $c_stat (a broken fixture)"
  u_full="$(ce_rows_full utf8)"
  [ "$u_full" = "$c_full" ] || fail "S230 collector-before/$name — rows 1-3 with the bytes before each marker differ under LANG=$MD_UTF8 (LC_ALL unset) from LC_ALL=C (a tr or grep ran without the C locale): $(printf '%s' "$u_full" | LC_ALL=C sed -E 's/^\| .* \| ([a-z-]+) \| .* \|$/\1/' | paste -sd/ -) vs $c_stat"

  # a done marker in the wrong shape, after the bytes: the loose-marker grep
  ce_before "Closes #265" "" "${pre}<!-- pre-merge-review:done sha=abc -->" "" ""
  c_full="$(ce_rows_full C)"
  md_has "$c_full" "not in the recognized" || fail "S230 collector-before-loose/$name — baseline under LC_ALL=C should say the done marker is not in the recognized shape, got: $c_full"
  u_full="$(ce_rows_full utf8)"
  [ "$u_full" = "$c_full" ] || fail "S230 collector-before-loose/$name — a malformed done marker after the bytes reads differently under LANG=$MD_UTF8 than under LC_ALL=C: $u_full"

  # marker-shaped text only in a code span, after the bytes: the quoted-suffix grep on the raw text
  ce_before "Closes #265" "" "${pre}\`<!-- pre-merge-review:done sha=$SHA -->\`" "" ""
  c_full="$(ce_rows_full C)"
  md_has "$c_full" "only inside a code span" || fail "S230 collector-before-quoted/$name — baseline under LC_ALL=C should say the done marker appears only inside a code span, got: $c_full"
  u_full="$(ce_rows_full utf8)"
  [ "$u_full" = "$c_full" ] || fail "S230 collector-before-quoted/$name — the quoted-suffix wording differs under LANG=$MD_UTF8 from LC_ALL=C: $u_full"
done

# =========================================================================
# 4. staleness: the verdict line
# =========================================================================
st_script="$TEST_REPO_ROOT/role-label-staleness.sh"
[ -x "$st_script" ] || { fail "S230 — role-label-staleness.sh is missing or not executable"; test_done; }
# shellcheck source=../fixtures/role-label-fake-gh.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/role-label-fake-gh.sh"

st_verdict() { # mode, marker
  local mode="$1" marker="$2" bin
  run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t%s\n' '$marker'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
  bin="$(cat "$FAKEGH_OUT")"
  case "$mode" in
    C) st_out="$(env LC_ALL=C PATH="$bin:$PATH" "$st_script" 400 2>/dev/null)" ;;
    utf8) st_out="$(env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" PATH="$bin:$PATH" "$st_script" 400 2>/dev/null)" ;;
  esac
  st_rc=$?
}
for name in $byte_names; do
  b="$(bytes_of "$name")"
  m="<!-- model-record: stage=Review model=\"claude-sonnet-5\" effort=\"medium\" floor-basis=\"x${b}y\" -->"
  st_verdict C "$m"
  c_verdict="$st_out"
  case "$c_verdict" in
    *" — stale "*) : ;;
    *) fail "S230 staleness/$name — baseline under LC_ALL=C: role:architect behind a stage=Review marker must be stale, got: $c_verdict" ;;
  esac
  st_verdict utf8 "$m"
  [ "$st_rc" -eq 0 ] || fail "S230 staleness/$name — exit $st_rc with LC_ALL unset and LANG=$MD_UTF8"
  [ "$st_out" = "$c_verdict" ] || fail "S230 staleness/$name — verdict under LANG=$MD_UTF8 is '$st_out', under LC_ALL=C '$c_verdict': live_text ran without the C locale"
done

# --- staleness: the bytes BEFORE the marker and the closing keyword -----------
# One variant per body source with its own tr site, and the two places the
# closing keyword lives (title only, body only): the keyword grep reads the
# live text after a byte, and the title/body tr sits before it.
st_before() { # mode, where
  local mode="$1" where="$2" pre="x${b}y " ib="" ic="plain comment" pt="Fix: something" pb="Closes #400" pc="plain" pr="plain" m bin
  m="${pre}<!-- model-record: stage=Review model=\"claude-sonnet-5\" effort=\"medium\" floor-basis=\"ok\" -->"
  case "$where" in
    issue-body) ib="$m" ;;
    issue-comment) ic="$m" ;;
    pr-body-marker) pb="Closes #400 $m" ;;
    pr-comment) pc="$m" ;;
    pr-review) pr="$m" ;;
    pr-title-keyword) pt="${pre}Closes #400: something"; pb="no keyword here"; pc="$m" ;;
    pr-body-keyword) pb="${pre}Closes #400"; pc="$m" ;;
  esac
  run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  printf 'BODY\t%s\n' '$ib'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  printf 'TEXT\t%s\n' '$ic'
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t%s\n' '$pt'
  printf 'BODY\t%s\n' '$pb'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t%s\n' '$pc'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  printf 'TEXT\t%s\n' '$pr'
  exit 0 ;;
GHEOF
  bin="$(cat "$FAKEGH_OUT")"
  case "$mode" in
    C) st_out="$(env LC_ALL=C PATH="$bin:$PATH" "$st_script" 400 2>/dev/null)" ;;
    utf8) st_out="$(env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" PATH="$bin:$PATH" "$st_script" 400 2>/dev/null)" ;;
  esac
}
for name in $byte_names; do
  b="$(bytes_of "$name")"
  for where in issue-body issue-comment pr-body-marker pr-comment pr-review pr-title-keyword pr-body-keyword; do
    st_before C "$where"
    c_verdict="$st_out"
    case "$c_verdict" in
      *" — stale "*) : ;;
      *) fail "S230 staleness-before/$name/$where — baseline under LC_ALL=C: role:architect behind a stage=Review marker must be stale, got: $c_verdict" ;;
    esac
    st_before utf8 "$where"
    [ "$st_out" = "$c_verdict" ] || fail "S230 staleness-before/$name/$where — verdict under LANG=$MD_UTF8 is '$st_out', under LC_ALL=C '$c_verdict': a tr or grep ran without the C locale"
  done
done

test_done
