#!/usr/bin/env bash
# S316 — the committed stamp matches the hash, and a stale stamp fails (#499 AC13)
# Covers: F38
#
# Seam: `orchestrator_diff.py stamp-check` (what ./check runs; it never calls a
# model) and the runner's stamp writer with the stub `claude` of S315.
#
# Pre-stamp state: A41 is silent on a tree with no stamp yet. Until the first
# passing differential run commits one, the real-tree check reports "no stamp
# yet" and passes. STAMP_REQUIRED below flips it to a failure; the rewrite phase
# turns it on together with the committed stamp.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/behavior-runner-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/behavior-runner-helpers.sh"

STAMP_REQUIRED=0
PY="$TEST_REPO_ROOT/test/behavior/orchestrator_diff.py"
[ -f "$PY" ] || { fail "S316 — test/behavior/orchestrator_diff.py is missing"; test_done; }
[ -x "$TEST_REPO_ROOT/test/behavior/orchestrator-diff.sh" ] || { fail "S316 — orchestrator-diff.sh is missing or not executable"; test_done; }
command -v python3 >/dev/null 2>&1 || { fail "S316 — python3 is needed"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
bf_init "$SANDBOX/bf"

# Real tree.
real_out="$(python3 -I "$PY" stamp-check --repo "$TEST_REPO_ROOT" 2>&1)"
real_status=$?
if [ -f "$TEST_REPO_ROOT/$BF_STAMP_REL" ]; then
  [ "$real_status" -eq 0 ] || fail "S316/real — the committed stamp does not match ORCHESTRATOR.md + scenarios: $real_out"
elif [ "$STAMP_REQUIRED" = 1 ]; then
  fail "S316/real — no stamp committed"
else
  grep -q 'no stamp yet' <<<"$real_out" || fail "S316/real — expected 'no stamp yet', got: $real_out"
  [ "$real_status" -eq 0 ] || fail "S316/real — a tree without a stamp must not fail before the first run (status $real_status)"
fi

# Fixture: a passing run writes the stamp.
bf_reset
bf_case 1 a dispatch 1 stop,stop,stop dispatch,dispatch,dispatch
bf_case 2 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_build
bf_run --runs 3 --model sonnet
[ "$bf_status" -eq 0 ] || fail "S316/write — passing run exited $bf_status: $bf_err"
ST="$BF_REPO/$BF_STAMP_REL"
[ -f "$ST" ] || { fail "S316/write — no stamp written by a passing run"; test_done; }
[ "$(wc -l <"$ST" | tr -d ' ')" = 1 ] || fail "S316/write — the stamp must be one line"
grep -Eq '^sha256=[0-9a-f]{64} base=[^ ]+ model=claude-stub-1 scenarios=2$' "$ST" || fail "S316/write — stamp format wrong: $(cat "$ST")"
want_hash="$(cat "$BF_REPO/$BF_ORCH_REL" "$BF_REPO/$BF_SCEN_REL" | shasum -a 256 | cut -d' ' -f1)"
grep -q "^sha256=$want_hash " "$ST" || fail "S316/write — hash is not SHA-256 over ORCHESTRATOR.md then the scenarios"

chk() { # chk <repo>: sets ck_out, ck_status. CLAUDE_BIN must never run.
  rm -f "$BF_DIR/model-was-called"
  ck_out="$(CLAUDE_BIN="$BF_FAILSTUB" python3 -I "$PY" stamp-check --repo "$1" 2>&1)"
  ck_status=$?
}
chk "$BF_REPO"
[ "$ck_status" -eq 0 ] || fail "S316/match — matching stamp failed: $ck_out"
[ ! -e "$BF_DIR/model-was-called" ] || fail "S316/match — the stamp check called a model"

# Stale fixtures: copy of the repo, one change each.
stale() { # stale <label> <function taking the copy dir>
  local d="$SANDBOX/stale-$1"
  rm -rf "$d"
  cp -R "$BF_REPO" "$d"
  "$2" "$d"
  chk "$d"
  [ "$ck_status" -ne 0 ] || fail "S316/stale-$1 — a stale stamp must fail"
}
byte_orch() { printf 'x' >>"$1/$BF_ORCH_REL"; }
byte_scen() { printf 'x' >>"$1/$BF_SCEN_REL"; }
swap_order() {
  local h
  h="$(cat "$1/$BF_SCEN_REL" "$1/$BF_ORCH_REL" | shasum -a 256 | cut -d' ' -f1)"
  sed "s/sha256=[0-9a-f]*/sha256=$h/" "$1/$BF_STAMP_REL" >"$1/s.tmp" && mv "$1/s.tmp" "$1/$BF_STAMP_REL"
}
add_intended() { printf -- '- OB2 (OR40): another fixture change, decided in #3.\n' >>"$1/$BF_SCEN_REL"; }
wrong_count() { sed 's/scenarios=2/scenarios=3/' "$1/$BF_STAMP_REL" >"$1/s.tmp" && mv "$1/s.tmp" "$1/$BF_STAMP_REL"; }
malformed() { echo "sha256=nothex base=x" >"$1/$BF_STAMP_REL"; }
stale byte-orchestrator byte_orch
stale byte-scenarios byte_scen
stale other-order swap_order
stale intended-list add_intended
stale scenario-count wrong_count
stale malformed malformed

# A run with a diverged scenario, and a run whose listed scenario's new arm misses
# Then, each leave the old stamp untouched.
before="$(cat "$ST")"
bf_reset
bf_case 1 a dispatch 0 dispatch,dispatch,dispatch stop,stop,stop
bf_build
bf_run --runs 3
[ "$bf_status" -ne 0 ] || fail "S316/diverged — exit must be non-zero"
[ "$(cat "$ST")" = "$before" ] || fail "S316/diverged — the stamp was touched"
bf_reset
bf_case 1 a dispatch 1 stop,stop,stop stop,stop,stop
bf_build
bf_run --runs 3
[ "$bf_status" -ne 0 ] || fail "S316/listed-miss — exit must be non-zero"
[ "$(cat "$ST")" = "$before" ] || fail "S316/listed-miss — the stamp was touched"

test_done
