#!/usr/bin/env bash
# S228 — v2 scanner and fields preserve invalid UTF-8 bytes under a UTF-8 LANG.
# Covers: F43
# Regression from the former tokenizer locale defect; the separate S230 K3
# mutation proves the actual external fence-awk C-prefix on native BSD.
# Seam: sourced rec_scan/rec_field with LC_ALL unset in a fresh shell.
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
  scan="$(rec_scan model-record "$body")"; echo "scan_rc=$?"
  printf "scan_out=%s\n" "$scan"
  find_out="$(rec_field "$body" model)"; echo "find_rc=$?"
  printf "find_out=%s\n" "$find_out"
  # Judged in the C locale: the value holds an invalid UTF-8 byte.
  LC_ALL=C
  case "$scan" in *"ok"*Test*) echo "scan_has_stage=1" ;; esac
  case "$find_out" in *"x"$'"'"'\377'"'"'"y"*) echo "find_has_value=1" ;; esac
' _ "$lib" 2>&1)"

case "$out" in
  *"scan_rc=0"*) ;;
  *) fail "S228 — rec_scan failed on a marker holding \\377 (LC_ALL unset, LANG=en_US.UTF-8): $out" ;;
esac
case "$out" in
  *"find_rc=0"*) ;;
  *) fail "S228 — rec_field failed on a marker holding \\377: $out" ;;
esac
# An empty result is red: `scan_out=` followed by a newline would satisfy a
# bare "something follows" pattern, so the checks are on content. rec_scan
# must report the marker's stage, rec_field must return the model
# that carries the \377 value.
case "$out" in
  *"scan_has_stage=1"*) ;;
  *) fail "S228 — rec_scan's output does not report the marker's stage Test (empty or vacuous): $out" ;;
esac
case "$out" in
  *"find_has_value=1"*) ;;
  *) fail "S228 — rec_field's output is empty or lacks the value carrying \\377: $out" ;;
esac

test_done
