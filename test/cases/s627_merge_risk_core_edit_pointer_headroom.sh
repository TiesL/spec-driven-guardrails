#!/usr/bin/env bash
# S627 — The core edit is a pointer, inside the slot headroom (#646)
# Covers: F74
#
# Seam: the bytes of skills/role-contracts/ORCHESTRATOR.md (OR11, OR43, OR6 as in
# A58 D2), the slot sizes from `session-context.sh --runtime claude --slot n`
# against CONTEXT_BUDGET_CHARS (sourced, never a literal) with the 500-character
# floor, policy/WORKFLOW.md step 4 and its generated projections
# (check-workflow-adapters.sh). The differential behavior run and its stamp are
# the orchestrator's (UNRUN here); the SNAPSHOTS re-pin is S548's.
# Mutation checks: OR11 grown, in a copy, by BUDGET - FLOOR + 1 - (slot 1 of
# that copy) characters (headroom fails) and by one fewer (control passes), so
# the verdict does not depend on the sandbox path length; the `#511` token
# removed (pointer check fails); a hand-edited projection (generator check fails).
#
# shellcheck disable=SC2016 # backticks are literal rule text, never expansions
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
sandbox_create
trap sandbox_destroy EXIT

MARKER='<!-- session-context: slot -->'
FLOOR=500
OR11_TAIL='Autonomy without per-PR approval: #511, only via accepted `merge-risk-panel` delegation.'
WF_SENTENCE='Merge autonomy without a per-PR approval is #511, not this rule. Only the accepted #646 delegation (the `merge-risk-panel` skill) provides it.'
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"
case "${CONTEXT_BUDGET_CHARS:-}" in
  ''|*[!0-9]*) fail "S627 — CONTEXT_BUDGET_CHARS is not a number"; test_done ;;
esac

clone() { # dest
  mkdir -p "$1"
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./wip' --exclude='./CLAUDE.md' \
    --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) | (cd "$1" && tar -xf -)
}

# S318's worst case: long clone and project paths (slot 1 names the clone path).
long="$(printf 'p%.0s' $(seq 1 100))"
proj="$SANDBOX/project-$long"
mkdir -p "$proj"
git -C "$proj" init -q -b main
ids=()
while IFS='|' read -r id value _; do
  case "$value" in session-context:*) ids+=("$id" yes) ;; esac
done < <(. "$TEST_REPO_ROOT/lib/changes.sh"; reaches_session_values "$TEST_REPO_ROOT/CHANGES.md")
write_adoption "$proj/WORKFLOW-ADOPTION.md" "${ids[@]}"
ln -s "$SANDBOX/nowhere/WORKFLOW.md" "$proj/CLAUDE.md"

slot_size() { # clone n
  local out
  out="$("$1/session-context.sh" --runtime claude --slot "$2" "$proj" 2>/dev/null; printf x)"
  out="${out%x}"
  printf '%s' "$out" | context_chars
}

# pointer_problems <clone>: prints one line per violated pointer rule.
pointer_problems() {
  local orch="$1/skills/role-contracts/ORCHESTRATOR.md" part1 or11 or43 or6
  [ "$(grep -cxF "$MARKER" "$orch")" = 1 ] || echo "K must stay 2 (exactly one marker line)"
  part1="$(sed "/^$MARKER\$/q" "$orch")"
  or11="$(grep -m1 '^- OR11 ' <<<"$part1")"
  or43="$(grep -m1 '^- OR43 ' <<<"$part1")"
  or6="$(grep -m1 '^- OR6 ' <<<"$part1")"
  grep -qF -- "$OR11_TAIL" <<<"$or11" || echo "OR11 lacks the pointer sentence: $or11"
  grep -qF -- '#511' <<<"$or11" || echo "OR11 lost the #511 token"
  grep -qF -- 'merges into `main` (OR11);' <<<"$or43" || echo "OR43 lacks (OR11): $or43"
  grep -qF -- 'confirmation before merge into `main` (OR11)' <<<"$or6" || echo "OR6 lacks (OR11): $or6"
  [ "$(grep -c 'merge-risk' "$orch")" = 1 ] || echo "procedure text entered the core: merge-risk named $(grep -c 'merge-risk' "$orch") times"
  grep -qE 'merge-risk-evidence|merge-autonomy|hold_seconds|--match-head-commit' "$orch" && echo "procedure text entered the core"
}

headroom_problems() { # clone
  local s1 s2
  s1="$(slot_size "$1" 1)"
  s2="$(slot_size "$1" 2)"
  [ $((CONTEXT_BUDGET_CHARS - s1)) -ge "$FLOOR" ] || echo "slot 1 is $s1 characters, headroom $((CONTEXT_BUDGET_CHARS - s1)) below $FLOOR (slot 2 is $s2)"
  [ $((CONTEXT_BUDGET_CHARS - s2)) -ge "$FLOOR" ] || echo "slot 2 is $s2 characters, headroom $((CONTEXT_BUDGET_CHARS - s2)) below $FLOOR (slot 1 is $s1)"
}

projection_problems() { # clone
  local f
  for f in policy/WORKFLOW.md WORKFLOW.md AGENTS.md adapters/codex/AGENTS.md; do
    grep -qF -- "$WF_SENTENCE" "$1/$f" || echo "$f lacks the step 4 delegation sentence"
  done
  (cd "$1" && ./check-workflow-adapters.sh >/dev/null 2>&1) || echo "check-workflow-adapters.sh is not clean"
}

wf="$SANDBOX/wf-$long"
clone "$wf"
s1="$(slot_size "$wf" 1)"
s2="$(slot_size "$wf" 2)"
echo "S627 sizes: slot1=$s1 slot2=$s2 budget=$CONTEXT_BUDGET_CHARS" >&2
while IFS= read -r p; do [ -n "$p" ] && fail "S627/pointer — $p"; done < <(pointer_problems "$wf")
while IFS= read -r p; do [ -n "$p" ] && fail "S627/headroom — $p"; done < <(headroom_problems "$wf")
while IFS= read -r p; do [ -n "$p" ] && fail "S627/projection — $p"; done < <(projection_problems "$wf")
# The meaning-version bump belongs to #679.
grep -qF '#646' "$TEST_REPO_ROOT/CHANGES.md" && fail "S627/meaning — CHANGES.md carries a #646 entry (that is #679's)"

# --- mutation checks ----------------------------------------------------------
m="$SANDBOX/m-$long"
clone "$m"
# grow_or11 <clone> <k>: k more characters inside OR11's pointer sentence.
grow_or11() {
  python3 -I - "$1/skills/role-contracts/ORCHESTRATOR.md" "$2" <<'PY'
import sys
p, k = sys.argv[1], int(sys.argv[2])
t = open(p, encoding="utf-8").read()
old = "only via accepted `merge-risk-panel` delegation"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, old + "y" * k))
PY
}
# Relative, as S318's neg-floor-1 (A58 addendum 5 D4): slot 1 is measured in
# this same copy, so the sandbox path (named in slot 1) is the same before and
# after the growth and the verdicts do not depend on its length.
s1_copy="$(slot_size "$m" 1)"
grow=$((CONTEXT_BUDGET_CHARS - FLOOR + 1 - s1_copy))
if [ "$grow" -lt 1 ]; then
  fail "S627/mutation — slot 1 of the copy ($s1_copy) leaves no headroom above $FLOOR to grow into"
else
  grow_or11 "$m" $((grow - 1))
  out="$(headroom_problems "$m")"
  [ -z "$out" ] || fail "S627/mutation-control — OR11 grown by $((grow - 1)) characters (headroom exactly $FLOOR) failed: $out"
  grow_or11 "$m" 1
  [ -n "$(headroom_problems "$m")" ] || fail "S627/mutation — OR11 grown by $grow characters (headroom $((FLOOR - 1))) kept the headroom: the floor does not bind (slot 1 of the copy was $s1_copy)"
fi

rm -rf "$m"; clone "$m"
sed -i.bak 's/approval: #511, only via/approval: only via/' "$m/skills/role-contracts/ORCHESTRATOR.md"
out="$(pointer_problems "$m")"
grep -qF 'lost the #511 token' <<<"$out" || fail "S627/mutation — removing the #511 token went unnoticed"

rm -rf "$m"; clone "$m"
printf '\nhand edit\n' >>"$m/WORKFLOW.md"
out="$(projection_problems "$m")"
grep -qF 'not clean' <<<"$out" || fail "S627/mutation — a hand-edited projection passed the generator check"

test_done
