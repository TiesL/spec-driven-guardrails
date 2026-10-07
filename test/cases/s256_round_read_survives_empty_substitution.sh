#!/usr/bin/env bash
# S256 — rr_rounds and the carry-forward gate treat "status 0 but nothing printed" from a tool that must print something as a failed read: a warning and no verdict, never "no round" and never a false finding
# Covers: F42, F28
#
# Issue #426 (slice V5 of #411); review round 1 of PR #452, finding
# empty-substitution-unguarded. On /bin/bash 3.2 a command substitution that cannot
# make its pipe returns status 0 and an empty value; a here-string whose temp file
# cannot be created returns 1. rec_scan guards this (it requires a numeric count);
# rr_rounds and the gate must not read an empty value from a non-empty input as an
# answer. Seam: counting PATH shims that run the real tool and then drop its stdout
# but keep its status (exactly what the broken substitution looks like from the
# caller), for tools whose output is never legitimately empty on a non-empty input:
# tr, sort, `grep -o` and `sed s///`.
#
# Threat model: ACCIDENTAL (fd or temp-file exhaustion, a failing fork). No forger.
#
#   L  rr_rounds (lib, sourced alone, rows with two rounds): with tr or sort
#      dropping its output from its 1st to its 3rd call, rr_rounds returns non-zero,
#      stdout is EMPTY, stderr has a line (never "no round" with status 0);
#   G  the gate (two rounds, a vanished finding): with tr, sort, `grep -o` or `sed s///`
#      dropping its output from its 1st to its 4th call: exit 0 (fail open), a
#      `warning` on stderr, NO finding line on stdout (no false "missing" from an
#      empty body, no silent "no round"). Every shim that was supposed to drop has
#      run (a vacuous pass is red);
#      (A blocked TMPDIR was tried and dropped: bash 3.2 does not read TMPDIR for
#      here-strings, so it injected nothing and proved nothing.)
#
# Kill table (mutants without the guard; each must fail the arm in brackets):
#   tr-unguarded     the decode of a body not checked for an empty result (L, G)
#   sort-unguarded   the sorted keys not checked for emptiness (L)
#   grep-o-unguarded the slug list from grep -o not checked (G)
#   sed-unguarded    the slug extraction not checked (G)

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/review-rounds-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"
# shellcheck source=../fixtures/review-rounds-lib-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-lib-helpers.sh"

GATE="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$GATE" ] || { fail "S256 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S256 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup
rrl_init "S256" || test_done

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
b1="r1${NL}$(rr_finding gone open)${NL}${rev}${NL}${dn}"
b2="r2, request changes${NL}${rev}"

# empty_shim <dir> <tool> <from> <counter> <only>: a PATH shim that runs the real tool and
# then drops its stdout, keeping the status, from the <from>-th call that <only> selects.
# only: all | grep-o (calls with -o in a flag cluster) | sed-s (calls with s/ and no -n).
# Every selected call is counted in <counter> (a shim never called is vacuous).
empty_shim() {
  local dir="$1" tool="$2" from="$3" counter="$4" only="$5" real
  real="$(command -v "$tool")" || { fail "S256 — no $tool on the PATH to shim"; return 1; }
  mkdir -p "$dir"
  {
    printf '#!/bin/sh\n'
    printf 'sel=1\n'
    case "$only" in
      grep-o) printf 'sel=0; for a in "$@"; do case "$a" in -*o*) sel=1 ;; esac; done\n' ;;
      sed-s) printf 'sel=0; for a in "$@"; do case "$a" in -n) sel=0; break ;; *s/*) sel=1 ;; esac; done\n' ;;
    esac
    printf 'if [ "$sel" = 1 ]; then echo x >> "%s"; n=0; while read -r _l; do n=$((n + 1)); done < "%s"; else n=0; fi\n' "$counter" "$counter"
    printf 'if [ "$sel" = 1 ] && [ "$n" -ge %s ]; then "%s" "$@" >/dev/null; exit $?; fi\n' "$from" "$real"
    printf 'exec "%s" "$@"\n' "$real"
  } >"$dir/$tool"
  chmod +x "$dir/$tool"
}
cnt() { if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }
n=0
fresh() { n=$((n + 1)); SHIMS="$SANDBOX/shims$n"; CNT="$SANDBOX/count$n"; rm -rf "$SHIMS" "$CNT"; mkdir -p "$SHIMS"; }

# ---- L: the lib ---------------------------------------------------------------------
rows="$(rrl_row "$T1" comment "$b1")${NL}$(rrl_row "$T2" review "$b2")"
rl_run() { # runs rr_rounds in a subshell with $SHIMS first on PATH; sets RL_OUT, RL_RC, RL_ERR
  RL_OUT="$( (PATH="$SHIMS:$PATH"; rr_rounds <<<"$rows") 2>"$SANDBOX/rl.err")"
  RL_RC=$?
  RL_ERR="$(cat "$SANDBOX/rl.err")"
}
for t in tr sort; do
  fresh
  empty_shim "$SHIMS" "$t" 99999 "$CNT" all || continue
  rl_run
  [ "$RL_RC" -eq 0 ] && [ "$(printf '%s' "$RL_OUT" | LC_ALL=C grep -ac '^R')" -eq 2 ] || fail "S256/L baseline $t — with a pass-through $t shim rr_rounds must give two rounds (rc=$RL_RC out='$RL_OUT' err='$RL_ERR')"
  total="$(cnt "$CNT")"
  [ "$total" -gt 0 ] || fail "S256/L baseline $t — the $t shim was never called: no failure of it can be injected (a vacuous pass is red)"
  for from in 1 2 3; do
    [ "$from" -le "$total" ] || continue
    fresh
    empty_shim "$SHIMS" "$t" "$from" "$CNT" all || continue
    rl_run
    if [ "$RL_RC" -eq 0 ]; then
      fail "S256/L $t from call $from — $t returned status 0 and printed nothing, and rr_rounds returned 0 too (out='$RL_OUT'): an empty substitution was read as an answer, 'no round'"
    fi
    [ -z "$RL_OUT" ] || fail "S256/L $t from call $from — rr_rounds printed rows although a read failed: '$RL_OUT'"
    [ -n "$RL_ERR" ] || fail "S256/L $t from call $from — rr_rounds failed without a line on stderr"
  done
done

# ---- G: the gate ----------------------------------------------------------------------
seed() {
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$b1"
  rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "$b2"
}
gate_with() { PATH="$SHIMS:$PATH" rr_script_run "$GATE" "$RR_PR"; }
for spec in "tr all" "sort all" "grep grep-o" "sed sed-s"; do
  t="${spec%% *}"
  only="${spec#* }"
  fresh
  seed
  empty_shim "$SHIMS" "$t" 99999 "$CNT" "$only" || continue
  gate_with
  [ "$(rr_gate_slugs)" = "gone" ] || fail "S256/G baseline $t — with a pass-through $t shim the gate must report 'gone' (stdout: $rr_out; stderr: $rr_err)"
  total="$(cnt "$CNT")"
  [ "$total" -gt 0 ] || fail "S256/G baseline $t — the $t ($only) shim was never called: no failure of it can be injected (a vacuous pass is red)"
  for from in 1 2 3 4; do
    [ "$from" -le "$total" ] || continue
    fresh
    seed
    empty_shim "$SHIMS" "$t" "$from" "$CNT" "$only" || continue
    gate_with
    [ "$rr_status" -eq 0 ] || fail "S256/G $t from call $from — exit $rr_status, expected 0 (fail open)"
    grep -qi 'warning' <<<"$rr_err" || fail "S256/G $t from call $from — $t printed nothing with status 0 and the gate said nothing on stderr: an empty substitution was taken for 'no round' or 'no finding' (stdout: $rr_out)"
    [ -z "$(printf '%s\n' "$rr_out" | LC_ALL=C grep -a '^finding-carryforward: ' || true)" ] || fail "S256/G $t from call $from — a verdict from a failed read: $rr_out"
  done
done

test_done
