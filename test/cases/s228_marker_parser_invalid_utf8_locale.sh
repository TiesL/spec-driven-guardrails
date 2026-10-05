#!/usr/bin/env bash
# S228 — The marker parser reads a body that holds an invalid UTF-8 byte
# inside a marker, with LC_ALL unset and LANG=en_US.UTF-8 (#422, AC3's
# precondition; the locale class of #392/#397).
# Covers: F43
#
# Regression scenario: green today because every awk call of
# lib/model-record.sh carries the `LC_ALL=C` prefix. Without it, BWK awk
# (macOS) aborts on `\377` inside a marker with "towc: multibyte conversion
# failure" and marker_scan returns 2. On a Linux runner (gawk) the same
# mutation can pass: the case that proves anything is the macOS leg.
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
' _ "$lib" 2>&1)"

case "$out" in
  *"scan_rc=0"*) ;;
  *) fail "S228 — marker_scan failed on a marker holding \\377 (LC_ALL unset, LANG=en_US.UTF-8): $out" ;;
esac
case "$out" in
  *"find_rc=0"*) ;;
  *) fail "S228 — marker_find failed on a marker holding \\377: $out" ;;
esac
case "$out" in
  *"scan_out="?*) ;;
  *) fail "S228 — marker_scan printed nothing for the marker (a vacuous pass): $out" ;;
esac

test_done
