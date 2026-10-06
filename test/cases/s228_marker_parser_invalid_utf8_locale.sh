#!/usr/bin/env bash
# S228 — The marker parser reads a body that holds an invalid UTF-8 byte
# inside a marker, with LC_ALL unset and LANG=en_US.UTF-8 (#422, AC3's
# precondition; the locale class of #392/#397).
# Covers: F43
#
# Regression scenario: green today because the awk calls of marker_scan and
# marker_find in lib/model-record.sh carry the `LC_ALL=C` prefix. Without it,
# BWK awk (macOS) aborts on `\377` inside a marker with "towc: multibyte
# conversion failure" and marker_scan returns 2. On a Linux runner (gawk) the
# same mutation can pass: the case that proves anything is the macOS leg.
# Guards marker_scan and marker_find only. marker_attr and marker_emit are NOT
# guarded: removing their LC_ALL=C does not abort on BWK awk (equivalent
# mutants), so no test of this kind can see it.
# MODEL_RECORD_LIB points the test at a scratch copy (mutation proof).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

lib="${MODEL_RECORD_LIB:-$TEST_REPO_ROOT/lib/model-record.sh}"
[ -f "$lib" ] || { fail "S228 — $lib is missing"; test_done; }

# A fresh bash with LC_ALL unset and a UTF-8 LANG; bytes via printf octal.
# shellcheck disable=SC2016
out="$(env -u LC_ALL -u LC_CTYPE LANG=en_US.UTF-8 bash -c '
  . "$1"
  body="$(printf "<!-- model-record: stage=Test model=\"x\377y\" effort=\"low\" -->\n")"
  scan="$(marker_scan "$body")"; echo "scan_rc=$?"
  printf "scan_out=%s\n" "$scan"
  find_out="$(marker_find Test "$body")"; echo "find_rc=$?"
  printf "find_out=%s\n" "$find_out"
  # Judged in the C locale: the value holds an invalid UTF-8 byte.
  LC_ALL=C
  case "$scan" in *"ok"*Test*) echo "scan_has_stage=1" ;; esac
  case "$find_out" in *"x"$'"'"'\377'"'"'"y"*) echo "find_has_value=1" ;; esac
' _ "$lib" 2>&1)"

case "$out" in
  *"scan_rc=0"*) ;;
  *) fail "S228 — marker_scan failed on a marker holding \\377 (LC_ALL unset, LANG=en_US.UTF-8): $out" ;;
esac
case "$out" in
  *"find_rc=0"*) ;;
  *) fail "S228 — marker_find failed on a marker holding \\377: $out" ;;
esac
# An empty result is red: `scan_out=` followed by a newline would satisfy a
# bare "something follows" pattern, so the checks are on content. marker_scan
# must report the marker's stage, marker_find must return the marker line
# that carries the \377 value.
case "$out" in
  *"scan_has_stage=1"*) ;;
  *) fail "S228 — marker_scan's output does not report the marker's stage Test (empty or vacuous): $out" ;;
esac
case "$out" in
  *"find_has_value=1"*) ;;
  *) fail "S228 — marker_find's output is empty or lacks the value carrying \\377: $out" ;;
esac

test_done
