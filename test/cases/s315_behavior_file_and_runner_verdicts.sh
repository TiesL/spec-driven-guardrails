#!/usr/bin/env bash
# S315 — the behavior file parses against the closed schema and the runner's verdict logic is right with a stub model (#499 AC11, AC12)
# Covers: F38
#
# Seams (A41): the scenario-file parser and the runner's verdict core
# (orchestrator_diff.py behind orchestrator-diff.sh), read as data with a stub
# `claude` named by CLAUDE_BIN. No model, gh or network call.
#
# Part A: the real scenario file parses; negative controls each fail by name.
# Part B: the runner against a fixture repo and the stub.
#
# Known pending (rewrite phase): rule-ID existence in the real file and the
# per-part-1-rule coverage need ORCHESTRATOR.md IDs and the inventory, which
# the rewrite adds; until then the real-file check reports that and skips.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/behavior-runner-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/behavior-runner-helpers.sh"

PY="$TEST_REPO_ROOT/test/behavior/orchestrator_diff.py"
RUNNER="$TEST_REPO_ROOT/test/behavior/orchestrator-diff.sh"
REAL_SCEN="$TEST_REPO_ROOT/$BF_SCEN_REL"
[ -f "$PY" ] || { fail "S315 — test/behavior/orchestrator_diff.py is missing"; test_done; }
[ -x "$RUNNER" ] || { fail "S315 — test/behavior/orchestrator-diff.sh is missing or not executable"; test_done; }
command -v python3 >/dev/null 2>&1 || { fail "S315 — python3 is needed"; test_done; }

sandbox_create
trap sandbox_destroy EXIT
bf_init "$SANDBOX/bf"

# --- Part A: parser -----------------------------------------------------------
parse() { # parse <scenario file> [<orchestrator file>]: sets pa_out, pa_status
  pa_out="$(python3 -I "$PY" check-scenarios --scenarios "$1" ${2:+--orchestrator "$2"} 2>&1)"
  pa_status=$?
}

parse "$REAL_SCEN"
[ "$pa_status" -eq 0 ] || fail "S315/real — the real scenario file does not parse: $pa_out"
n_ob="$(grep -c '^### OB' "$REAL_SCEN")"
grep -q "scenarios=$n_ob" <<<"$pa_out" || fail "S315/real — parser did not report scenarios=$n_ob: $pa_out"
ob9="$(grep -A3 '^### OB9 ' "$REAL_SCEN")"
grep -q '^Then: .*next_action=ask_human' <<<"$ob9" \
  || fail "S315/real — OB9 (stricter OR11) must have next_action=ask_human"

# A valid small fixture and an orchestrator with IDs.
FX="$SANDBOX/fx"
mkdir -p "$FX"
cat >"$FX/orch.md" <<'ORCH'
# Rules

- OR9 Contract quote.
- OR11 Merge only after confirmation.
- OR12 Fresh Reviewer.
ORCH
cat >"$FX/good.md" <<'GOOD'
# Fixture

## Cases

### OB9 · OR11
Given: A commit landed after the confirmation.
When: You are about to merge.
Then: next_action=ask_human; asks_human=true

### OB10 · OR11, OR12
Given: Head unchanged.
When: You act.
Then: next_action=merge; next_role=none; low_finding=defer; model_choice=weaker; starts_pipeline=false

## Intended changes

Prose line.

- OB9 (OR11): a commit after the confirmation needs a new one.
  Decided by the maintainer (#513, recorded on #499).
GOOD
parse "$FX/good.md" "$FX/orch.md"
[ "$pa_status" -eq 0 ] || fail "S315/control — the valid fixture must parse: $pa_out"

# neg <label> <expected fragment> <sed args>: a broken copy must fail naming the defect.
neg() {
  local label="$1" frag="$2"
  shift 2
  sed "$@" "$FX/good.md" >"$FX/bad.md"
  parse "$FX/bad.md" "$FX/orch.md"
  [ "$pa_status" -ne 0 ] || fail "S315/$label — the broken copy parsed"
  grep -q -- "$frag" <<<"$pa_out" || fail "S315/$label — expected '$frag' in: $pa_out"
}
neg unknown-value "next_action=continue" -e 's/next_action=ask_human/next_action=continue/'
neg unknown-low-finding "low_finding=maybe" -e 's/low_finding=defer/low_finding=maybe/'
neg unknown-field "bogus" -e 's/starts_pipeline=false/bogus=1/'
neg missing-when "OB10: missing When" -e '/^When: You act\./d'
neg unknown-rule "OR99" -e 's/^### OB9 · OR11$/### OB9 · OR99/'
neg or-in-given "Given cites" -e 's/^Given: A commit landed/Given: Under OR11 a commit landed/'
neg duplicate-ob "OB9: duplicate" -e 's/^### OB10 · OR11, OR12/### OB9 · OR11, OR12/'
neg intended-unknown-ob "OB99" -e 's/^- OB9 (OR11)/- OB99 (OR11)/'
neg intended-or-differs "OB9: OR list" -e 's/^- OB9 (OR11)/- OB9 (OR12)/'
neg intended-no-decision "no #" -e 's/(#513, recorded on #499)/(recorded)/'
neg missing-then "OB9: missing Then" -e '/^Then: next_action=ask_human/d'
neg reason-in-then "reason" -e 's/asks_human=true/reason=because/'
# the same OB listed twice
{ cat "$FX/good.md"; printf -- '- OB9 (OR11): again. Decided in #2.\n'; } >"$FX/bad.md"
parse "$FX/bad.md" "$FX/orch.md"
{ [ "$pa_status" -ne 0 ] && grep -q 'OB9: listed twice' <<<"$pa_out"; } \
  || fail "S315/intended-twice — expected 'OB9: listed twice' failure: $pa_out"

# --- Part B: runner with the stub ---------------------------------------------
# Verdict cases, one run. bf_case <num> <tag> <then> <listed> <old> <new>.
bf_reset
bf_case 1 a dispatch 1 stop,stop,stop dispatch,dispatch,dispatch
bf_case 2 b dispatch 1 dispatch,dispatch,dispatch stop,stop,stop
bf_case 3 c dispatch 1 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_case 4 d dispatch 0 stop,stop,stop dispatch,dispatch,dispatch
bf_case 5 e dispatch 1 dispatch,stop,ask_human dispatch,dispatch,dispatch
bf_case 6 f dispatch 0 dispatch,dispatch,dispatch dispatch,stop,ask_human
bf_case 7 g dispatch 1 dispatch,dispatch,dispatch dispatch,stop,ask_human
bf_case 8 h dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_case 9 i dispatch 1 stop,stop,stop stop,stop,stop
bf_case 10 j dispatch 0 dispatch,dispatch,stop dispatch,dispatch,stop
bf_case 11 k dispatch 0 dispatch,stop,stop dispatch,dispatch,dispatch
bf_build
bf_run --runs 3 --model sonnet
want() { # want <num> <verdict>
  local got
  got="$(bf_verdict "$1")"
  [ "$got" = "$2" ] || fail "S315/verdict OB$1 — got '$got', want '$2'. Output: $bf_out"
}
want 1 changed-as-intended # listed, old wrong, new right
want 2 diverged            # listed, new wrong, old right
want 3 same                # listed and both right
want 4 old-wrong           # unlisted, old wrong, new right
want 5 changed-as-intended # listed, old unstable (1-1-1), new right
want 6 unstable            # unlisted, new unstable
want 7 unstable            # listed, new unstable
want 8 same
want 9 old-wrong           # listed, both wrong: new does not meet Then
want 10 same               # 2 of 3 is a majority (new arm equal Then)... old 2 of 3 dispatch
want 11 old-wrong          # old: 2 of 3 stop, a majority that misses Then
[ "$bf_status" -ne 0 ] || fail "S315/exit — a run with old-wrong, diverged and unstable must exit non-zero"

# Exit 0 only when every scenario is same or changed-as-intended.
bf_reset
bf_case 1 a dispatch 1 stop,stop,stop dispatch,dispatch,dispatch
bf_case 2 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_build
bf_run --runs 3
[ "$bf_status" -eq 0 ] || fail "S315/exit — same + changed-as-intended must exit 0 (status $bf_status): $bf_err $bf_out"
rm -f "$BF_REPO/$BF_STAMP_REL"

# The prompt never carries Then; the call carries the isolation flags; empty scratch cwd.
saw_calls=0
for f in "$STUB_DIR"/call-*.prompt; do
  [ -e "$f" ] || continue
  saw_calls=$((saw_calls + 1))
  { grep -q 'Given:' "$f" && grep -q 'When:' "$f"; } || fail "S315/prompt — $(basename "$f") lacks Given or When"
  if grep -q 'Then' "$f" || grep -q 'next_action=' "$f"; then fail "S315/prompt — $(basename "$f") leaks Then"; fi
done
[ "$saw_calls" -eq 12 ] || fail "S315/calls — 2 scenarios x 2 arms x 3 runs = 12 calls, saw $saw_calls"
args="$(tr '\0' '\n' <"$STUB_DIR/call-1.args")"
for flag in --strict-mcp-config --no-session-persistence --json-schema --tools --setting-sources --settings --output-format -p --system-prompt-file; do
  grep -qx -- "$flag" <<<"$args" || fail "S315/args — call 1 lacks $flag"
done
grep -q 'disableAllHooks' <<<"$args" || fail "S315/args — call 1 lacks disableAllHooks"
if grep -qx -- '--bare' <<<"$args"; then fail "S315/args — --bare must not be used"; fi
# --tools and --setting-sources take an empty string
printf '%s\n' "$args" | awk 'p=="--tools" && $0=="" {t=1} p=="--setting-sources" && $0=="" {s=1} {p=$0} END {exit !(t && s)}' \
  || fail "S315/args — --tools and --setting-sources must be followed by an empty string"
cwd="$(cat "$STUB_DIR/call-1.cwd")"
[ "$(cat "$STUB_DIR/call-1.cwdcount")" = 0 ] || fail "S315/cwd — call ran in a non-empty directory ($cwd)"
case "$cwd" in "$BF_REPO"*|"$TEST_REPO_ROOT"*) fail "S315/cwd — call ran inside a repo ($cwd)" ;; esac

# Arm texts: old = base revision, new = working tree, marker dropped, same preamble.
grep -q 'OLDTEXT' "$STUB_DIR/seen-OLD.txt" || fail "S315/arms — old arm is not the base revision text"
grep -q 'NEWTEXT' "$STUB_DIR/seen-NEW.txt" || fail "S315/arms — new arm is not the working-tree text"
if grep -q 'NEWTEXT' "$STUB_DIR/seen-OLD.txt"; then fail "S315/arms — old arm contains the new text"; fi
if grep -q 'session-context: slot' "$STUB_DIR/seen-NEW.txt"; then fail "S315/arms — marker line not dropped from the new arm"; fi
# the preamble starts after the rule lines; compare what follows the "- OR40" line
pre_old="$(sed -n '/^- OR40/,$p' "$STUB_DIR/seen-OLD.txt" | sed '1d')"
pre_new="$(sed -n '/^- OR40/,$p' "$STUB_DIR/seen-NEW.txt" | sed '1d')"
{ [ -n "$pre_old" ] && [ "$pre_old" = "$pre_new" ]; } || fail "S315/arms — the two arms do not carry the same fixed preamble"
# the Schema definitions, word for word
missing=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  grep -qF -- "$line" "$STUB_DIR/seen-NEW.txt" || { missing=1; echo "    missing in preamble: $line" >&2; }
done < <(sed -n '/^## Schema/,/^## Role and pipeline/p' "$REAL_SCEN" | sed '$d')
[ "$missing" -eq 0 ] || fail "S315/preamble — the Schema definitions are not carried word for word"

# No use of timeout: a failing `timeout` ahead on PATH must not be hit.
mkdir -p "$SANDBOX/bin"
printf '#!/bin/sh\ntouch "%s/timeout-called"\nexit 99\n' "$SANDBOX" >"$SANDBOX/bin/timeout"
chmod +x "$SANDBOX/bin/timeout"
bf_reset
bf_case 1 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_build
PATH="$SANDBOX/bin:$PATH" bf_run --runs 3
[ ! -e "$SANDBOX/timeout-called" ] || fail "S315/timeout — the runner called timeout (absent on macOS)"
[ "$bf_status" -eq 0 ] || fail "S315/timeout — run failed: $bf_err"
rm -f "$BF_REPO/$BF_STAMP_REL"

# Report columns and resolved model id.
grep -qF '| scenario | old | new | Then | verdict | model | cost |' <<<"$bf_out" || fail "S315/report — column header missing: $bf_out"
grep -q 'claude-stub-1' <<<"$bf_out" || fail "S315/report — resolved model id missing"

# Budget: stops before the call that would pass the cap, and says so.
bf_reset
bf_case 1 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_case 2 h dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_build
STUB_COST=0.50 bf_run --runs 3 --max-budget-usd 1.2
[ "$bf_status" -ne 0 ] || fail "S315/budget — a budget stop must exit non-zero"
grep -qi 'budget' <<<"$bf_err" || fail "S315/budget — no budget message: $bf_err"
[ "$(cat "$STUB_DIR/n" 2>/dev/null)" = 2 ] || fail "S315/budget — expected 2 calls (cap 1.2, 0.50 each), saw $(cat "$STUB_DIR/n" 2>/dev/null)"
[ ! -e "$BF_REPO/$BF_STAMP_REL" ] || fail "S315/budget — a stopped run must not write a stamp"

# Baseline (old against old): unlisted all same -> 0, listed old-wrong reported and tolerated.
bf_reset
bf_case 1 a dispatch 1 stop,stop,stop stop,stop,stop
bf_case 2 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_build
bf_run --runs 3 --baseline
[ "$bf_status" -eq 0 ] || fail "S315/baseline — listed old-wrong + unlisted same must pass (status $bf_status): $bf_err"
[ "$(bf_verdict 1)" = old-wrong ] || fail "S315/baseline — listed scenario should be reported old-wrong, got '$(bf_verdict 1)'"
[ "$(bf_verdict 2)" = same ] || fail "S315/baseline — OB2 should be same"
[ ! -e "$BF_REPO/$BF_STAMP_REL" ] || fail "S315/baseline — baseline must not write a stamp"
grep -q 'OLDTEXT' "$STUB_DIR/seen-NEW.txt" || fail "S315/baseline — the second arm must carry the old text too"
bf_reset
bf_case 1 a dispatch 0 stop,stop,stop stop,stop,stop
bf_build
bf_run --runs 3 --baseline
[ "$bf_status" -ne 0 ] || fail "S315/baseline — an unlisted old-wrong must fail the baseline"

# Calibration: A/A noise floor plus a mutant (one never/not removed in OR40).
bf_reset
bf_case 1 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch stop,stop,stop
bf_build
bf_run --runs 3 --calibrate --mutant-rule OR40
[ "$bf_status" -eq 0 ] || fail "S315/calibrate — a detected mutant must exit 0 (status $bf_status): $bf_err $bf_out"
if [ -f "$STUB_DIR/seen-MUT.txt" ]; then
  grep -q 'OR40 Fix it in the PR; defer a low finding' "$STUB_DIR/seen-MUT.txt" || fail "S315/calibrate — mutant lacks the removed 'never' on OR40"
  grep -q 'OR1 Start the pipeline' "$STUB_DIR/seen-MUT.txt" || fail "S315/calibrate — mutant changed more than one rule"
  [ "$(diff <(grep -v 'session-context: slot' "$BF_REPO/$BF_ORCH_REL" | tr ' ' '\n') <(sed -n '1,/^- OR40/p' "$STUB_DIR/seen-MUT.txt" | tr ' ' '\n') | grep -c '^[<>]')" = 1 ] \
    || fail "S315/calibrate — mutant differs from the new text by other than one word"
else
  fail "S315/calibrate — no mutant arm was run"
fi
grep -q 'diverged' <<<"$bf_out" || fail "S315/calibrate — mutant row should be diverged: $bf_out"
grep -qi 'noise' <<<"$bf_out$bf_err" || fail "S315/calibrate — noise floor not reported"
# a blind test (mutant answers like the new text) fails calibration
bf_reset
bf_case 1 c dispatch 0 dispatch,dispatch,dispatch dispatch,dispatch,dispatch dispatch,dispatch,dispatch
bf_build
bf_run --runs 3 --calibrate --mutant-rule OR40
[ "$bf_status" -ne 0 ] || fail "S315/calibrate — an undetected mutant must exit non-zero"

test_done
