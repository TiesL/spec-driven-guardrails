#!/usr/bin/env bash
# test/fixtures/markdown-helpers.sh — helpers shared by S230-S233 (#423, V2 of
# #411). Source after test/lib.sh and sandbox_create. Not a test case.
#
# Bash 3.2, BWK awk, BSD grep/sed clean: no declare -A, no mapfile, no
# ${var,,}, no GNU-only flags; every external command that reads bytes of a
# body carries the per-command `LC_ALL=C`, and grep is `grep -a`.

# shellcheck disable=SC2034  # the MD_* constants are used by the cases that source this file

# Raw byte classes the cases use (command substitution keeps them as bytes).
MD_FF="$(printf '\377')"                # a byte that is invalid UTF-8
MD_TRUNC="$(printf '\342\200')"         # a truncated 3-byte sequence
MD_EMDASH="$(printf '\342\200\224')"    # a valid multibyte character
MD_LF=$'\n'
MD_CR=$'\r'

# md_utf8_locale: prints a UTF-8 locale installed here (en_US.UTF-8 first, as
# the A35a mutation proof names it), or nothing.
md_utf8_locale() {
  local avail cand
  avail="$(locale -a 2>/dev/null)"
  for cand in en_US.UTF-8 C.UTF-8 en_US.utf8 C.utf8; do
    if LC_ALL=C grep -aqix -- "$cand" <<<"$avail"; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

# md_need_locale <label>: sets MD_UTF8 or fails loudly. On the macOS leg a
# missing UTF-8 locale is a failure, never a skip (A35a K3); elsewhere the
# UTF-8 arm is reported as skipped and the function returns 1.
md_need_locale() {
  MD_UTF8="$(md_utf8_locale)" && return 0
  if [ "$(uname -s)" = "Darwin" ]; then
    fail "$1 — no UTF-8 locale installed on a macOS host (tried en_US.UTF-8 C.UTF-8); the locale arms cannot run and are never skipped there"
  else
    echo "    NOTE: $1 — no UTF-8 locale installed here; the UTF-8 arms are skipped (they must run on the macOS leg)" >&2
  fi
  return 1
}

# md_has <text> <needle>: the needle occurs in the text (byte-wise).
md_has() {
  case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

# md_lines <text>: number of lines in the text ("" is 0).
md_lines() {
  if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | LC_ALL=C wc -l | tr -d ' '; fi
}

# md_has_cr <text>: the text holds a CR byte.
md_has_cr() {
  case "$1" in *"$MD_CR"*) return 0 ;; *) return 1 ;; esac
}

# md_run_lib <C|utf8> <function> <body>: runs the function of lib/markdown.sh
# in a fresh bash. "C" -> LC_ALL=C. "utf8" -> LC_ALL and LC_CTYPE unset and
# LANG=$MD_UTF8 (the A35a shape). Sets MD_OUT (stdout, trailing newlines
# trimmed) and MD_RC. The library path comes from MD_LIB (default: the repo's
# own), so a mutation proof can point at a scratch copy.
MD_RC=0
MD_OUT=""
md_run_lib() {
  local mode="$1" fn="$2" body="$3"
  local lib="${MD_LIB:-$TEST_REPO_ROOT/lib/markdown.sh}"
  case "$mode" in
    C)
      # shellcheck disable=SC2016  # the program text is meant to expand in the child
      env LC_ALL=C bash -c '. "$1"; "$2" "$3"' _ "$lib" "$fn" "$body" > "$SANDBOX/md.out" 2> "$SANDBOX/md.err"
      MD_RC=$?
      ;;
    utf8)
      # shellcheck disable=SC2016
      env -u LC_ALL -u LC_CTYPE LANG="$MD_UTF8" bash -c '. "$1"; "$2" "$3"' _ "$lib" "$fn" "$body" > "$SANDBOX/md.out" 2> "$SANDBOX/md.err"
      MD_RC=$?
      ;;
  esac
  MD_OUT="$(cat "$SANDBOX/md.out")"
}

# md_live_of <body>: live_text of a body in the C locale; MD_OUT, MD_RC.
md_live_of() { md_run_lib C live_text "$1"; }

# --- the counting awk shim --------------------------------------------------
# make_awk_shim <dir>: an `awk` in <dir> that counts every call in
# $AWK_SHIM_COUNT, exits 2 for calls whose number is in
# [$AWK_SHIM_FAIL_FROM, $AWK_SHIM_FAIL_TO] (defaults: never), and otherwise
# runs the real awk ($AWK_SHIM_REAL). A case that never reaches the shim is
# vacuous and must be red: always assert the count.
make_awk_shim() {
  mkdir -p "$1"
  cat > "$1/awk" <<'SHIM'
#!/bin/sh
n=0
[ -r "$AWK_SHIM_COUNT" ] && n="$(cat "$AWK_SHIM_COUNT")"
n=$((n + 1))
echo "$n" > "$AWK_SHIM_COUNT"
from="${AWK_SHIM_FAIL_FROM:-0}"
to="${AWK_SHIM_FAIL_TO:-0}"
if [ "$from" -gt 0 ] && [ "$n" -ge "$from" ] && [ "$n" -le "$to" ]; then
  echo "awk: injected failure (call $n)" >&2
  exit 2
fi
exec "$AWK_SHIM_REAL" "$@"
SHIM
  chmod +x "$1/awk"
}

# md_expect <label> <fn> <body> <expected>: fn of lib/markdown.sh under LC_ALL=C
# exits 0 and prints exactly <expected> (trailing newlines trimmed). One FAIL
# line per case; a stub (exit 99, empty) is red here, never exit 127.
md_expect() {
  local label="$1" fn="$2" body="$3" want="$4"
  md_run_lib C "$fn" "$body"
  if [ "$MD_RC" -ne 0 ]; then
    fail "$label — $fn exit $MD_RC, expected 0"
    return 1
  fi
  if [ "$MD_OUT" != "$want" ]; then
    fail "$label — $fn: expected $(printf '%q' "$want"), got $(printf '%q' "$MD_OUT")"
    return 1
  fi
  return 0
}

# md_live <label> <body> <inside-needle> <live-needle>: live_text exits 0, the
# output no longer holds <inside-needle> (quoted) and still holds
# <live-needle> (a live marker). Empty needle = not asserted.
md_live() {
  local label="$1" body="$2" quoted="$3" live="$4"
  md_run_lib C live_text "$body"
  if [ "$MD_RC" -ne 0 ]; then
    fail "$label — live_text exit $MD_RC, expected 0"
    return 1
  fi
  if [ -n "$quoted" ] && md_has "$MD_OUT" "$quoted"; then
    fail "$label — '$quoted' must be quoted (blanked) but is live: $(printf '%q' "$MD_OUT")"
  fi
  if [ -n "$live" ] && ! md_has "$MD_OUT" "$live"; then
    fail "$label — '$live' must be live but is gone: $(printf '%q' "$MD_OUT")"
  fi
}
