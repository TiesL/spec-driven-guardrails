#!/usr/bin/env bash
# S252 — the carry-forward gate calls only `gh api repos/{owner}/{repo}/...` (comments and reviews), fails open with a warning when a fetch fails, and a failed read is a warning, never "no round" and never a false finding
# Covers: F28, F42
#
# Issue #426 (slice V5 of #411) AC3; A34 ("moves to REST ... returns 403 inside
# a Claude Code session, #318"), A37, A32a (an external tool failure is a
# failure, never "no record"). Seam: the real gate against a recording fake gh
# (REST data) and counting PATH shims.
#
# Threat model: ACCIDENTAL (a fetch that fails or half fails, a tool that exits
# 2, GraphQL refused by the host). No forger.
#
#   R1 every gh call is `gh api repos/{owner}/{repo}/...` and a plain GET; the PR's
#      comments and the PR's reviews are both read; no `pr view`, no GraphQL;
#      nothing is written to the working directory;
#   R2 the fetch fails (everything, the comments only, the reviews only; the data is
#      built so that each endpoint ALONE would give a verdict): exit 0, a warning on
#      stderr, NO finding on stdout (a half-read PR must not give a verdict). No gh at
#      all: the same, without a call;
#   R3 the read fails (a tool exits 2): exit 0, a warning on stderr, nothing on stdout,
#      for grep and awk, and for every other tool the gate turns out to call (sed,
#      tr, cut, sort, head, tail, uniq, wc) from its 1st to its 4th call, and
#      every shim that was supposed to fail has run (a vacuous pass is red);
#      grep's exit 1 stays a plain "no hit" (a clean PR, with nothing open or
#      with a carried finding, prints nothing and warns of nothing);
#   R4 static: the gate defines no rr_rounds, live_text or md_strip_fences, sources
#      lib/review-rounds.sh, carries no model-record or stage= pattern of its own, no
#      `gh pr`, no eval, and runs under /bin/bash 3.2 where that exists; its first
#      statement is `export LC_ALL=C` (S235 holds the same line to a lint).
#
# Red today: the gate calls `gh pr view` (R1, R3 baseline), and has no
# export or lib (R4). Kill table:
#   graphql      `gh pr view --json comments` (R1; the fake refuses it, like #318)
#   write        a gh call with -X/-f (R1)
#   one-endpoint read only one of the two endpoints (R1)
#   fail-closed  exit 1 on a failed fetch (R2)
#   silent       no warning on a failed fetch (R2)
#   half         a verdict from the comments when the reviews fetch failed (R2)
#   fail-open-tool a failing sed/tr/grep/awk read as "no finding" or as a finding (R3)
#   grep-1       grep exit 1 treated as a failure (R3 clean run warns)
#   own-parser   a model-record pattern, an own rr_rounds (R4)

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
# shellcheck source=../fixtures/record-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/record-helpers.sh"

GATE="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$GATE" ] || { fail "S252 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S252 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
# two rounds, one finding that vanished: the gate has a verdict to give
seed() {
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(rr_finding gone open)${NL}${rev}${NL}${dn}"
  rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at "$T2" "r2, request changes${NL}${rev}"
}
verdict() { [ "$(rr_gate_slugs)" = "gone" ]; }

# ---- R1 REST only -----------------------------------------------------------------
seed
: > "$RR_LOG"
rr_script_run "$GATE" "$RR_PR"
verdict || fail "S252/R1 — baseline: the vanished finding was not reported (stdout: $rr_out; stderr: $rr_err), so the call checks below prove nothing"
[ "$(wc -l < "$RR_LOG" | tr -d ' ')" -ge 2 ] || fail "S252/R1 — the gate made fewer than two gh calls: $(cat "$RR_LOG")"
grep -q "issues/$RR_PR/comments" "$RR_LOG" || fail "S252/R1 — the PR's comments (issues/$RR_PR/comments) were not fetched"
grep -q "pulls/$RR_PR/reviews" "$RR_LOG" || fail "S252/R1 — the PR's reviews (pulls/$RR_PR/reviews) were not fetched: a PR review is a round"
while IFS= read -r call; do
  [ -n "$call" ] || continue
  case "$call" in
    "api repos/{owner}/{repo}/"*) : ;;
    *) fail "S252/R1 — a gh call that is not 'gh api repos/{owner}/{repo}/...' (GraphQL-backed, 403 in Claude Code, #318): gh $call" ;;
  esac
  if grep -qE -- '(^| )(-X|--method|-f|-F|--field|--raw-field|--input)( |=|$)|graphql' <<<"$call"; then
    fail "S252/R1 — a gh api call that is not a plain GET: gh $call"
  fi
done < "$RR_LOG"
[ -z "$(find "$RR_CWD" -mindepth 1 2>/dev/null)" ] || fail "S252/R1 — the gate left files in its working directory: $(ls "$RR_CWD")"

# ---- R2 a failed fetch fails open, with a warning, and gives no verdict ---------------
check_open() { # <label>: exit 0, a warning, no finding line on stdout
  [ "$rr_status" -eq 0 ] || fail "S252/R2 $1 — exit $rr_status, expected 0 (fail open)"
  grep -qiE 'warning' <<<"$rr_err" || fail "S252/R2 $1 — no warning on stderr (silent success): stderr='$rr_err'"
  [ -z "$(printf '%s\n' "$rr_out" | grep -a '^finding-carryforward: ' || true)" ] || fail "S252/R2 $1 — a verdict from a PR that could not be read: $rr_out"
}
seed
FAKE_GH_FAIL=1 rr_script_run "$GATE" "$RR_PR"
check_open "gh fails"
# data where EACH endpoint alone gives a verdict: a half-read PR must give none
T3=2026-10-03T10:00:00Z T4=2026-10-04T10:00:00Z
seed_halves() {
  rr_reset
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at \
    "$T1" "c1${NL}$(rr_finding gone-c open)${NL}${rev}${NL}${dn}" "$T2" "c2${NL}${rev}${NL}${dn}"
  rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at \
    "$T3" "v1${NL}$(rr_finding gone-v open)${NL}${rev}" "$T4" "v2${NL}${rev}"
}
seed_halves
rr_script_run "$GATE" "$RR_PR"
[ "$(rr_gate_slugs | LC_ALL=C tr '\n' ' ')" = "gone-c gone-v " ] \
  || fail "S252/R2 — baseline: with both endpoints readable the gate must report gone-c and gone-v (got: $rr_out; stderr: $rr_err), so the half-read checks prove nothing"
for gone in "comments-$RR_PR" "reviews-$RR_PR"; do
  seed_halves
  rm -f "${FAKE_GH_DATA:?}/${gone:?}.json"
  rr_script_run "$GATE" "$RR_PR"
  check_open "$gone unreadable"
done
nogh="$SANDBOX/nogh"
mkdir -p "$nogh"
for p in /usr/bin/* /bin/*; do
  b="${p##*/}"
  [ "$b" = gh ] && continue
  [ -e "$nogh/$b" ] || ln -s "$p" "$nogh/$b" 2>/dev/null
done
if [ -z "$(PATH="$nogh" command -v gh 2>/dev/null)" ]; then
  seed
  nogh_out="$(cd "$RR_CWD" && PATH="$nogh" "$GATE" "$RR_PR" 2>"$SANDBOX/nogh-err")"
  nogh_status=$?
  [ "$nogh_status" -eq 0 ] || fail "S252/R2 — exit $nogh_status without gh, expected 0"
  grep -qiE 'warning' "$SANDBOX/nogh-err" || fail "S252/R2 — no warning on stderr without gh"
  [ -z "$nogh_out" ] || fail "S252/R2 — output without gh: $nogh_out"
fi

# ---- R3 a failed read is a warning, never "no round", never a false finding -----------
tools="grep awk sed tr cut head tail sort uniq wc"
n=0
fresh() { n=$((n + 1)); SHIMS="$SANDBOX/shims$n"; CNT="$SANDBOX/count$n"; rm -rf "$SHIMS" "$CNT"; mkdir -p "$SHIMS"; }
gate_shimmed() { PATH="$SHIMS:$PATH" rr_script_run "$GATE" "$RR_PR"; }
# the shims go ahead of the PATH the fake gh was put on; rr_run adds RR_BIN in front
fresh
seed
for t in $tools; do rh_shim "$SHIMS" "$t" pass "$CNT.$t" || continue; done
gate_shimmed
verdict || fail "S252/R3 baseline — with pass-through shims the gate must still report the vanished finding (stdout: $rr_out; stderr: $rr_err)"
base_grep="$(rh_count "$CNT.grep")"
base_awk="$(rh_count "$CNT.awk")"
for t in grep awk; do
  [ "$(rh_count "$CNT.$t")" -gt 0 ] || fail "S252/R3 baseline — the $t shim was never called: no failure of it can be injected (a vacuous pass is red)"
done
for t in $tools; do
  for from in 1 2 3 4; do
    lim=0
    case "$t" in grep) lim="$base_grep" ;; awk) lim="$base_awk" ;; esac
    # a failure from call N is only injected when the baseline run made N calls
    if [ "$lim" -gt 0 ] && [ "$from" -gt "$lim" ]; then continue; fi
    fresh
    seed
    rh_shim "$SHIMS" "$t" "failafter:$from" "$CNT" || continue
    gate_shimmed
    c="$(rh_count "$CNT")"
    case "$t" in grep | awk) [ "$c" -ge "$from" ] || fail "S252/R3 $t from call $from — the $t shim ran only $c times: the failure was never injected" ;; esac
    if [ "$c" -ge "$from" ]; then
      [ "$rr_status" -eq 0 ] || fail "S252/R3 $t from call $from — exit $rr_status, expected 0 (fail open)"
      grep -qiE 'warning' <<<"$rr_err" || fail "S252/R3 $t from call $from — $t exited 2 and the gate said nothing on stderr: a failed read was taken for 'no round' or 'no finding'"
      [ -z "$(printf '%s\n' "$rr_out" | grep -a '^finding-carryforward: ' || true)" ] || fail "S252/R3 $t from call $from — a verdict from a failed read (stdout: $rr_out)"
    fi
  done
done
# grep exit 1 is "no hit": a PR with no round at all is clean, silent, status 0
fresh
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "prose only" "$T2" "more prose"
rrl_shim_dir="$SHIMS"
mkdir -p "$rrl_shim_dir"
{
  printf '#!/bin/sh\n'
  printf 'echo x >> "%s"\n' "$CNT"
  # shellcheck disable=SC2016  # written into the shim, not expanded here
  printf 'for a in "$@"; do case "$a" in -*c*) echo 0 ;; esac; done\nexit 1\n'
} > "$rrl_shim_dir/grep"
chmod +x "$rrl_shim_dir/grep"
gate_shimmed
[ "$rr_status" -eq 0 ] && [ -z "$rr_out" ] && ! grep -qi 'warning' <<<"$rr_err" \
  || fail "S252/R3 grep exit 1 — grep's exit 1 is 'no hit': a PR without a round gives status 0, nothing on stdout and no warning; got rc=$rr_status out='$rr_out' err='$rr_err'"
[ "$(rh_count "$CNT")" -gt 0 ] || fail "S252/R3 grep exit 1 — the grep shim was never called (a vacuous pass is red)"

# a clean PR (two rounds, nothing open; and one finding carried): grep finds nothing for the
# finding markers (exit 1) and that is no failure: exit 0, no warning, no output
fresh
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}${rev}${NL}${dn}" "$T2" "r2${NL}${rev}${NL}${dn}"
for tool in grep sed; do rh_shim "$SHIMS" "$tool" pass "$CNT.$tool" || continue; done
gate_shimmed
[ "$rr_status" -eq 0 ] && [ -z "$rr_out" ] && ! grep -qi 'warning' <<<"$rr_err" \
  || fail "S252/R3 clean — two rounds without any finding give status 0, nothing on stdout and no warning (grep's exit 1 on a body without a marker is no failure); got rc=$rr_status out='$rr_out' err='$rr_err'"
[ "$(rh_count "$CNT.grep")" -gt 0 ] || fail "S252/R3 clean — the grep shim was never called (a vacuous pass is red)"
fresh
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "r1${NL}$(rr_finding kept open)${NL}${rev}${NL}${dn}" "$T2" "r2${NL}$(rr_finding kept open)${NL}${rev}${NL}${dn}"
rh_shim "$SHIMS" grep pass "$CNT.grep" || true
gate_shimmed
[ "$rr_status" -eq 0 ] && [ -z "$rr_out" ] && ! grep -qi 'warning' <<<"$rr_err" \
  || fail "S252/R3 clean — a carried finding gives status 0, nothing on stdout and no warning; got rc=$rr_status out='$rr_out' err='$rr_err'"

# ---- R4 static ---------------------------------------------------------------------
code="$(grep -vE '^[[:space:]]*#' "$GATE")"
grep -qE '^export LC_ALL=C' <<<"$code" || fail "S252/R4 — the gate does not export LC_ALL=C (A32c: it reads GitHub text)"
grep -qE 'lib/review-rounds\.sh' <<<"$code" || fail "S252/R4 — the gate does not source lib/review-rounds.sh (A37: one definition of a round)"
grep -qE '(^|[^A-Za-z_])rr_rounds([^A-Za-z_]|$)' <<<"$code" || fail "S252/R4 — the gate does not call rr_rounds"
for fn in rr_rounds live_text md_strip_fences; do
  grep -qE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\\(\\)" <<<"$code" && fail "S252/R4 — the gate defines $fn; it is defined only in lib/ (T1)"
done
if grep -qE 'model-record:|stage=|pipeline-override' <<<"$code"; then
  fail "S252/R4 — the gate carries record text of its own: $(grep -nE 'model-record:|stage=|pipeline-override' <<<"$code" | head -2)"
fi
if grep -qE 'gh (pr|issue) |gh api graphql|graphql|(^|[^a-z])eval ' <<<"$code"; then
  fail "S252/R4 — the gate has a GraphQL-backed gh call or an eval: $(grep -nE 'gh (pr|issue) |graphql|(^|[^a-z])eval ' <<<"$code" | head -2)"
fi
if grep -qE 'declare -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|grep -[a-zA-Z]*P|sed -[a-zA-Z]*i|date -d|readlink -f|xargs -r|stat -c' <<<"$code"; then
  fail "S252/R4 — the gate uses a bash 4 or GNU-only construct: $(grep -nE 'declare -A|mapfile|readarray|grep -[a-zA-Z]*P|sed -[a-zA-Z]*i|date -d' <<<"$code" | head -2)"
fi
if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]' 2>/dev/null; then
  seed
  want="$(rr_gate_slugs; true)"
  b32="$(cd "$RR_CWD" && PATH="$RR_BIN:$PATH" /bin/bash "$GATE" "$RR_PR" 2>"$SANDBOX/b32-err")"
  # one line, the fixed prefix, then (S254) the round it names
  case "$b32" in
    "finding-carryforward: gone was open in the previous round and is missing from this one"*) [ "$(printf '%s\n' "$b32" | wc -l | tr -d ' ')" -eq 1 ] || fail "S252/R4 bash32 — more than one line: $b32" ;;
    *) fail "S252/R4 bash32 — under /bin/bash 3.2 the output differs or the gate failed ($want): $b32 / $(cat "$SANDBOX/b32-err")" ;;
  esac
fi

test_done
