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

# row_status of the shared fixture runs sed in the ambient locale, which errors
# on an invalid byte in the evidence text; this one pins LC_ALL=C.
row_st() { # output n
  printf '%s\n' "$1" | LC_ALL=C sed -n "$(($2 + 2))p" | LC_ALL=C sed -E 's/^\| .* \| ([a-z-]+) \| .* \|$/\1/'
}
ce_rows() { # mode: prints "<row1>/<row2>/<row3>" statuses of the last-built fake gh
  local mode="$1" bin out
  bin="$(cat "$FAKEGH_OUT")"
  case "$mode" in
    C) out="$(env LC_ALL=C PATH="$bin:$PATH" "$ce_script" 279 2>/dev/null)" ;;
    utf8) out="$(env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" PATH="$bin:$PATH" "$ce_script" 279 2>/dev/null)" ;;
  esac
  printf '%s/%s/%s' "$(row_st "$out" 1)" "$(row_st "$out" 2)" "$(row_st "$out" 3)"
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
  c_rows="$(ce_rows C)"
  [ "$c_rows" = "evidenced/evidenced/evidenced" ] || fail "S230 collector/$name — baseline under LC_ALL=C: rows 1-3 should be evidenced/evidenced/evidenced, got $c_rows (a broken fixture)"
  u_rows="$(ce_rows utf8)"
  [ "$u_rows" = "$c_rows" ] || fail "S230 collector/$name — rows 1-3 under LANG=$MD_UTF8 (LC_ALL unset) are $u_rows, under LC_ALL=C $c_rows: live_text ran without the C locale"
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

test_done
