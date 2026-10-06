#!/usr/bin/env bash
# S247 — a reader failure is never "no record": when an external tool fails, rec_scan and rec_scan_bundle return non-zero with EMPTY stdout; grep's exit 1 (no hit) is not a failure; the shim must have run (R6)
# Covers: F40
#
# Issue #425 (slice V4 of #411), AC5; A32a ("Exit codes": for grep, exit 1 means
# no hit and is not a failure, exit 2 or more is a failure; a failure prints
# nothing on stdout and one line on stderr, and returns non-zero). The QA
# critique D10: failure injection must not be implementation-coupled and must
# not pass vacuously. So the failing tool is a PATH shim (test/fixtures/
# record-helpers.sh: rh_shim) that counts its own calls, for EVERY external
# tool the lib might call, and the case asserts on what happened:
#   - grep and awk are the two tools A32 names for the reader; for those two the
#     pass-through run must call the shim (count > 0), else the case is red,
#     whatever the reader did;
#   - for any other tool the lib turns out to use (sed, tr, cut, wc, ...), a
#     failure of it from the first call, and from the second, third and fourth,
#     must also fail the reader whenever the shim actually failed (count >=
#     the failing call number), and a tool the reader never calls is simply
#     not exercised;
#   - a failure on the Nth call must fail the WHOLE read with empty stdout: no
#     rows of the earlier bodies leak out of a failed bundle.
# `[[ =~ ]]` returning 2 (a pattern that did not compile) is also a failure in
# the design; it cannot be injected from outside and is a stated limit of this
# case.
#
# Threat model: ACCIDENTAL: a dropped `|| return`, a pipeline whose status is
# the last command's, `$(...)` swallowing a status, grep's exit 2 read as "no
# match". The #397 class: a tool error turned into "no marker", which the
# gate reads as a missing stage (or worse, as a pass).
#
# Red today: stubs (return 99): the pass-through baseline already fails (no ok
# row, the shim never called). Mutations this case must not survive (kill
# table): drop a `|| return` after the grep or awk; treat grep exit 2 like exit
# 1; treat grep exit 1 as a failure (every body without a record then fails);
# print rows collected so far before returning the failure; a reader that does
# not call grep (the shim count is 0, red).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rh_init "S247" || test_done

LF=$'\n'
REC="$(rh_rec Test m-one)"
REC2="$(rh_rec Review m-two 'floor-basis="f"')"
with_record="intro${LF}${REC}${LF}outro"
without_record="just prose, no comment at all${LF}and a second line"
bundle5="$(rh_join_bundle "$REC" "x" "$REC2" "${REC}${LF}${REC2}" "$REC")"
tools="grep awk sed tr cut wc head tail sort uniq"

mode_list="C"
case "$RH_MODES" in *LANG*) mode_list="C LANG" ;; esac

n=0
fresh() { n=$((n + 1)); SHIMS="$SANDBOX/shims$n"; CNT="$SANDBOX/count$n"; rm -rf "$SHIMS" "$CNT"; mkdir -p "$SHIMS"; }

# --- 1. the harness itself: pass-through shims for every tool, record body ----
for mode in $mode_list; do
  for fn in rec_scan rec_scan_bundle; do
    fresh
    for t in $tools; do rh_shim "$SHIMS" "$t" pass "$CNT.$t" || continue 2; done
    if [ "$fn" = rec_scan ]; then arg="$with_record"; else arg="$bundle5"; fi
    rh_run "$mode" rh_with_path "$SHIMS" "$fn" model-record "$arg"
    if [ "$RH_RC" -ne 0 ] || ! rh_rows || [ "$RH_N" -lt 1 ] || [ "${RH_CLS[0]}" != ok ]; then
      fail "S247/baseline $fn [$mode] — with pass-through shims the reader must still read the record (rc=$RH_RC, out='$RH_OUT', err='$RH_ERR')"
    fi
    for t in grep awk; do
      c="$(rh_count "$CNT.$t")"
      [ "$c" -gt 0 ] || fail "S247/baseline $fn [$mode] — the $t shim was never called: the reader does not use $t through the PATH, so no failure of it can be injected (a vacuous pass is red)"
    done
  done
done

# --- 2. grep exits 2 on a body with a record: failure, empty stdout -------------
for mode in $mode_list; do
  for fn in rec_scan rec_scan_bundle; do
    if [ "$fn" = rec_scan ]; then arg="$with_record"; else arg="$bundle5"; fi
    for t in grep awk; do
      fresh
      rh_shim "$SHIMS" "$t" fail "$CNT" || continue
      rh_run "$mode" rh_with_path "$SHIMS" "$fn" model-record "$arg"
      c="$(rh_count "$CNT")"
      [ "$c" -gt 0 ] || fail "S247/$t exit 2 $fn [$mode] — the $t shim was never called (count $c): the scenario proved nothing"
      [ "$RH_RC" -ne 0 ] || fail "S247/$t exit 2 $fn [$mode] — status 0 although $t failed: a reader failure was read as no record (stdout: '$RH_OUT')"
      [ -z "$RH_OUT" ] || fail "S247/$t exit 2 $fn [$mode] — stdout must be empty when the reader failed, got: '$RH_OUT'"
      [ -n "$RH_ERR" ] || fail "S247/$t exit 2 $fn [$mode] — a failure says so on stderr (one line at least)"
    done
  done
done

# --- 3. grep exit 1 is "no hit", not a failure -------------------------------------
for mode in $mode_list; do
  for fn in rec_scan rec_scan_bundle; do
    fresh
    rh_shim "$SHIMS" grep nohit "$CNT" || continue
    if [ "$fn" = rec_scan ]; then arg="$without_record"; else arg="$(rh_join_bundle "$without_record" "more prose" "")"; fi
    rh_run "$mode" rh_with_path "$SHIMS" "$fn" model-record "$arg"
    [ "$RH_RC" -eq 0 ] || fail "S247/grep exit 1 $fn [$mode] — grep's exit 1 (no match) on a body without a record is not a failure; got status $RH_RC (stderr: '$RH_ERR')"
    [ -z "$RH_OUT" ] || fail "S247/grep exit 1 $fn [$mode] — no record, no rows; got '$RH_OUT'"
    [ -z "$RH_ERR" ] || fail "S247/grep exit 1 $fn [$mode] — a clean 'no hit' says nothing on stderr; got '$RH_ERR'"
  done
done

# --- 4. any tool, failing from the Nth call: the whole read fails, nothing leaks ----
# (the first mode only: the sweep is tools x call numbers x two functions)
sweep_modes=C
for mode in $sweep_modes; do
  for fn in rec_scan rec_scan_bundle; do
    if [ "$fn" = rec_scan ]; then arg="$with_record"; else arg="$bundle5"; fi
    for t in $tools; do
      for from in 1 2 3 4; do
        fresh
        rh_shim "$SHIMS" "$t" "failafter:$from" "$CNT" || continue
        rh_run "$mode" rh_with_path "$SHIMS" "$fn" model-record "$arg"
        c="$(rh_count "$CNT")"
        if [ "$c" -ge "$from" ]; then
          # the shim failed at least once: the read must have failed, with nothing on stdout
          [ "$RH_RC" -ne 0 ] || fail "S247/$t from call $from $fn [$mode] — $t failed (called $c times) but the status is 0: a failure read as success (stdout: '$RH_OUT')"
          [ -z "$RH_OUT" ] || fail "S247/$t from call $from $fn [$mode] — $t failed but stdout is not empty (partial rows leak out of a failed read): '$RH_OUT'"
        else
          # the shim never failed (the tool is called fewer than $from times): a clean read
          [ "$RH_RC" -eq 0 ] || fail "S247/$t from call $from $fn [$mode] — $t was called only $c times (never failed) yet the read failed with $RH_RC: '$RH_ERR'"
        fi
        if [ "$t" = grep ] || [ "$t" = awk ]; then
          [ "$from" -ne 1 ] || [ "$c" -ge 1 ] || fail "S247/$t from call 1 $fn [$mode] — the $t shim was never called"
        fi
      done
    done
  done
done

# --- 5. rec_field: never an empty success when a tool fails ---------------------------
line='<!-- model-record: stage=Review model="m1" floor-basis="the real one" -->'
for mode in $mode_list; do
  fresh
  for t in $tools; do rh_shim "$SHIMS" "$t" fail "$CNT.$t" || continue 2; done
  rh_run "$mode" rh_with_path "$SHIMS" rec_field "$line" floor-basis
  if [ "$RH_RC" -eq 0 ]; then
    [ "$RH_OUT" = "the real one" ] || fail "S247/rec_field [$mode] — with every external tool failing, rec_field returned status 0 and '$RH_OUT': a wrong or empty value with status 0 reads as 'no such attribute'"
  else
    [ -z "$RH_OUT" ] || fail "S247/rec_field [$mode] — a failed rec_field must print nothing, got '$RH_OUT'"
  fi
done

test_done
