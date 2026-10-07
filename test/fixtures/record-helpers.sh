#!/usr/bin/env bash
# test/fixtures/record-helpers.sh — helpers shared by S242-S249 and S204 (#425,
# V4 of #411). Source after test/lib.sh. Not a test case.
#
# What these helpers are for: running the record reader (rec_scan_bundle,
# rec_scan, rec_field of lib/model-record.sh) under the three locale
# environments the production scripts meet, and turning its rows into shell
# variables a case can compare. They judge nothing about HOW the reader parses
# (tdd-seams): a row is four tab-separated fields, in the order the issue pins.
#
# Bash 3.2, BWK awk, BSD grep/sed/tr clean: no declare -A, no mapfile, no
# ${var,,}, no GNU-only flags; every external command that touches bytes of a
# body carries the per-command `LC_ALL=C`, and grep is `grep -a`.
#
# The three locale environments (A32a, the QA critique D1):
#   C     LC_ALL=C, LANG unset
#   UTF8  LC_ALL and LANG both a UTF-8 locale
#   LANG  LC_ALL UNSET, LANG a UTF-8 locale. This is how production runs a
#         sourced lib: `local LC_ALL=C` does not reach a child process in
#         bash 3.2, and BWK awk aborts on an invalid byte in a UTF-8 locale.
# A UTF-8 locale that is not installed is a failure on a macOS host and a
# reported skip elsewhere (md_need_locale, test/fixtures/markdown-helpers.sh).

# shellcheck disable=SC2034,SC2030,SC2031  # RH_* are read by the cases; the locale env is set in subshells on purpose

# shellcheck source-path=SCRIPTDIR
# shellcheck source=markdown-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/markdown-helpers.sh"

RH_SEP=$'\036'   # U+001E, the bundle's body separator (MARKER_SEP)
RH_TAB=$'\t'
RH_LF=$'\n'

# rh_init <label>: sources the lib, finds the UTF-8 locale and sets RH_MODES
# (space separated). Returns 1 when the lib is missing (the case then ends).
rh_init() {
  local label="$1" lib="$TEST_REPO_ROOT/lib/model-record.sh"
  if [ ! -f "$lib" ]; then
    fail "$label — lib/model-record.sh is missing"
    return 1
  fi
  # shellcheck source=../../lib/model-record.sh disable=SC1091
  . "$lib"
  local fn
  for fn in rec_scan_bundle rec_scan rec_field; do
    type "$fn" >/dev/null 2>&1 || {
      fail "$label — lib/model-record.sh defines no $fn"
      return 1
    }
  done
  RH_MODES="C"
  if md_need_locale "$label"; then
    RH_MODES="C UTF8 LANG"
  fi
  RH_ERRF="$SANDBOX/rh.err"
  return 0
}

# rh_run <mode> <command...>: runs the command (a function or program) in a
# subshell with the mode's locale environment. Sets RH_OUT (stdout, trailing
# newlines trimmed by $(...)), RH_RC and RH_ERR (stderr).
rh_run() {
  local mode="$1"
  shift
  case "$mode" in
    C) RH_OUT="$( (unset LANG; export LC_ALL=C; "$@") 2>"$RH_ERRF")" ;;
    UTF8) RH_OUT="$( (export LC_ALL="$MD_UTF8" LANG="$MD_UTF8"; "$@") 2>"$RH_ERRF")" ;;
    LANG) RH_OUT="$( (unset LC_ALL; export LANG="$MD_UTF8"; "$@") 2>"$RH_ERRF")" ;;
    *) fail "rh_run — unknown mode '$mode'"; return 1 ;;
  esac
  RH_RC=$?
  RH_ERR="$(LC_ALL=C tr -d '\000' <"$RH_ERRF" 2>/dev/null)"
  return 0
}

# rh_rows: parses RH_OUT into RH_N and the arrays RH_IDX, RH_CLS, RH_STG,
# RH_TXT (the fourth field is the rest of the row, tabs included). Returns 1
# and sets RH_BAD when a row is not four fields with the first three non-empty,
# the index is not a positive integer, or the class is not ok, near-miss or
# quoted. The shape rule the issue pins: "no field is ever empty".
rh_rows() {
  RH_N=0
  RH_IDX=()
  RH_CLS=()
  RH_STG=()
  RH_TXT=()
  RH_BCLS=()    # per body index: its classes, space separated (O(1) lookups: a bundle can hold thousands of rows)
  RH_BFIRST=()  # per body index: the ordinal of its first row
  RH_BCNT=()    # per body index: how many rows it has
  RH_BAD=""
  [ -n "$RH_OUT" ] || return 0
  local row idx cls stg txt rest prev=0
  while IFS= read -r row; do
    case "$row" in
      *"$RH_TAB"*"$RH_TAB"*"$RH_TAB"*) : ;;
      *)
        RH_BAD="row without four tab-separated fields: '$row'"
        return 1
        ;;
    esac
    idx="${row%%"$RH_TAB"*}"
    rest="${row#*"$RH_TAB"}"
    cls="${rest%%"$RH_TAB"*}"
    rest="${rest#*"$RH_TAB"}"
    stg="${rest%%"$RH_TAB"*}"
    txt="${rest#*"$RH_TAB"}"
    case "$idx" in
      '' | *[!0-9]* | 0)
        RH_BAD="body index '$idx' is not a positive integer (indices count from 1): '$row'"
        return 1
        ;;
    esac
    case "$cls" in
      ok | near-miss | quoted) : ;;
      *)
        RH_BAD="class '$cls' is not ok, near-miss or quoted: '$row'"
        return 1
        ;;
    esac
    if [ -z "$stg" ] || [ -z "$txt" ]; then
      RH_BAD="an empty stage or line/reason field ('?' stands for unknown): '$row'"
      return 1
    fi
    if [ "$idx" -lt "$prev" ]; then
      RH_BAD="rows are not in body order (index $idx after $prev): '$row'"
      return 1
    fi
    prev="$idx"
    if [ -z "${RH_BCNT[$idx]-}" ]; then
      RH_BFIRST[idx]="$RH_N"
      RH_BCNT[idx]=0
      RH_BCLS[idx]=""
    fi
    RH_BCNT[idx]=$((RH_BCNT[idx] + 1))
    RH_BCLS[idx]="${RH_BCLS[$idx]}${RH_BCLS[$idx]:+ }$cls"
    RH_IDX[RH_N]="$idx"
    RH_CLS[RH_N]="$cls"
    RH_STG[RH_N]="$stg"
    RH_TXT[RH_N]="$txt"
    RH_N=$((RH_N + 1))
  done <<EOF
$RH_OUT
EOF
  return 0
}

# rh_classes: the classes of the parsed rows, space separated ("ok near-miss").
rh_classes() {
  local i out=""
  i=0
  while [ "$i" -lt "$RH_N" ]; do
    out="$out${out:+ }${RH_CLS[$i]}"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# rh_scan <label> <mode> <kind> <body>: rec_scan under <mode>, then rh_rows.
# A non-zero exit status, text on stderr-only failure or a malformed row is a
# failure of its own. Returns 1 when the rows cannot be used.
rh_scan() {
  local label="$1" mode="$2"
  shift 2
  rh_run "$mode" rec_scan "$@"
  if [ "$RH_RC" -ne 0 ]; then
    fail "$label [$mode] — rec_scan exited $RH_RC (stdout: '$RH_OUT', stderr: '$RH_ERR')"
    RH_N=0
    return 1
  fi
  if ! rh_rows; then
    fail "$label [$mode] — $RH_BAD"
    return 1
  fi
  return 0
}

# rh_bundle <label> <mode> <kind> <bundle>: rec_scan_bundle, likewise.
rh_bundle() {
  local label="$1" mode="$2"
  shift 2
  rh_run "$mode" rec_scan_bundle "$@"
  if [ "$RH_RC" -ne 0 ]; then
    fail "$label [$mode] — rec_scan_bundle exited $RH_RC (stdout: '$RH_OUT', stderr: '$RH_ERR')"
    RH_N=0
    return 1
  fi
  if ! rh_rows; then
    fail "$label [$mode] — $RH_BAD"
    return 1
  fi
  return 0
}

# rh_field <mode> <line> <name>: rec_field's stdout (RH_OUT) and status.
rh_field() {
  local mode="$1"
  shift
  rh_run "$mode" rec_field "$@"
}

# rh_join_bundle <body...>: the bundle form: each body with U+001E removed
# first (the callers' convention, A32a), then followed by U+001E. Prints it.
rh_join_bundle() {
  local b out=""
  for b in "$@"; do
    out="$out${b//$RH_SEP/}$RH_SEP"
  done
  printf '%s' "$out"
}

# rh_classes_for <index>: the classes of the rows of one body index, in order.
rh_classes_for() {
  printf '%s' "${RH_BCLS[$1]-}"
}

# rh_text_for <index> <class> [n]: the fourth field of the n-th (default 1st)
# row of that body index and class; prints nothing and returns 1 if none.
rh_text_for() {
  local want="$1" cls="$2" nth="${3:-1}" i seen=0 last
  [ -n "${RH_BCNT[$want]-}" ] || return 1
  i="${RH_BFIRST[$want]}"
  last=$((i + RH_BCNT[want]))
  while [ "$i" -lt "$last" ]; do
    if [ "${RH_CLS[$i]}" = "$cls" ]; then
      seen=$((seen + 1))
      if [ "$seen" -eq "$nth" ]; then
        printf '%s' "${RH_TXT[$i]}"
        return 0
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

# rh_stage_for <index> <class> [n]: the stage field of that row.
rh_stage_for() {
  local want="$1" cls="$2" nth="${3:-1}" i seen=0 last
  [ -n "${RH_BCNT[$want]-}" ] || return 1
  i="${RH_BFIRST[$want]}"
  last=$((i + RH_BCNT[want]))
  while [ "$i" -lt "$last" ]; do
    if [ "${RH_CLS[$i]}" = "$cls" ]; then
      seen=$((seen + 1))
      if [ "$seen" -eq "$nth" ]; then
        printf '%s' "${RH_STG[$i]}"
        return 0
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

# rh_ok_fields <label> <mode> <line> <name> <want>: the line read through
# rec_field gives exactly <want> for <name>.
rh_expect_field() {
  local label="$1" mode="$2" line="$3" name="$4" want="$5"
  rh_field "$mode" "$line" "$name"
  if [ "$RH_RC" -ne 0 ]; then
    fail "$label [$mode] — rec_field '$name' exited $RH_RC on an ok line (stderr: '$RH_ERR')"
    return 1
  fi
  if [ "$RH_OUT" != "$want" ]; then
    fail "$label [$mode] — rec_field '$name' gave '$RH_OUT', want '$want'"
    return 1
  fi
  return 0
}

# rh_shim <dir> <tool> <mode> <counter>: writes an executable PATH shim for
# <tool> into <dir>. Every call appends one line to <counter> first (the count
# proves the shim was in the path of the code under test: a scenario whose shim
# is never called is vacuous, QA critique D10). Then, by <mode>:
#   pass         runs the real tool (found on the PATH now) unchanged
#   fail         prints one stderr line and exits 2 (a tool failure), every call
#   failafter:N  passes the first N-1 calls through, fails from the N-th on
#   nohit        exits 1 and prints nothing (grep's "no match")
# The shim uses only shell builtins, so it never re-enters the shim directory.
rh_shim() {
  local dir="$1" tool="$2" mode="$3" counter="$4" real n=1
  real="$(command -v "$tool")" || {
    fail "rh_shim — no $tool on the PATH to shim"
    return 1
  }
  case "$mode" in
    failafter:*) n="${mode#failafter:}" ;;
    fail) n=1 ;;
  esac
  mkdir -p "$dir"
  {
    printf '#!/bin/sh\n'
    printf 'echo x >> "%s"\n' "$counter"
    case "$mode" in
      pass) printf 'exec "%s" "$@"\n' "$real" ;;
      # what a real `grep -c` prints and returns when nothing matches: "0", exit 1
      nohit) printf 'echo 0\nexit 1\n' ;;
      # exit 1 with NO count: the status bash itself gives a command it could not
      # run, so it is not a "no hit" (review round 1, F1)
      silent1) printf 'exit 1\n' ;;
      # exit 0 with NO count: bash 3.2 gives a failed command substitution status 0
      # and an empty value, so "grep ran, printed nothing" is also no count
      silent0) printf 'exit 0\n' ;;
      fail | failafter:*)
        # shellcheck disable=SC2016  # written into the shim, not expanded here
        printf 'n=0; while read -r _l; do n=$((n + 1)); done < "%s"\n' "$counter"
        # shellcheck disable=SC2016  # written into the shim, not expanded here
        printf 'if [ "$n" -ge %s ]; then echo "%s: injected failure" >&2; exit 2; fi\n' "$n" "$tool"
        printf 'exec "%s" "$@"\n' "$real"
        ;;
    esac
  } >"$dir/$tool"
  chmod +x "$dir/$tool"
}

# rh_with_path <dir> <command...>: runs the command with <dir> first on PATH
# (use it through rh_run, which runs it in a subshell).
rh_with_path() {
  local d="$1"
  shift
  PATH="$d:$PATH"
  export PATH
  "$@"
}

# rh_count <counter>: how many times the shim ran.
rh_count() {
  if [ -f "$1" ]; then
    LC_ALL=C grep -ac . "$1"
  else
    echo 0
  fi
}

# A valid record line builder, so a case never retypes the grammar:
#   rh_rec <Stage> <model> [<extra attributes text>]
# prints <!-- model-record: stage=<Stage> model="<model>"[ <extra>] -->
rh_rec() {
  local extra=""
  [ -z "${3-}" ] || extra=" $3"
  printf '<!-- model-record: stage=%s model="%s"%s -->' "$1" "$2" "$extra"
}

# rh_fence_for <string>: sets RH_FENCE to a backtick fence one character longer
# than the longest backtick run in <string> (at least three): the wrap the issue
# asks for, so no run in the line can close it.
rh_fence_for() {
  local rest="$1" run longest=0 ticks='`+'
  while [[ $rest =~ ($ticks) ]]; do
    run="${#BASH_REMATCH[1]}"
    [ "$run" -le "$longest" ] || longest="$run"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  RH_FENCE='```'
  while [ "${#RH_FENCE}" -le "$longest" ]; do RH_FENCE="$RH_FENCE\`"; done
}
