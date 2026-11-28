#!/usr/bin/env bash
# S309 — the one session-context output is within budget in the worst case, carries no rule text, and is wired as one SessionStart command without --slot (#499 AC4, AC6; amended by #750 A66 D2)
# Covers: F38
#
# Seam (A41 as amended by A66): `session-context.sh [--runtime R] <project>`
# output, measured by `context_chars` of lib/context-budget.sh against
# CONTEXT_BUDGET_CHARS (sourced, never a literal here), and
# settings/session-hooks.json read as data. Worst case: every CHANGES.md
# entry that declares `opt-in-loaded:` answered yes, the CLAUDE.md link
# broken and the core link missing so both warnings print, clone and project
# paths of 100+ characters. File name kept for history (slots are gone).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/core-delivery-750.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/core-delivery-750.sh"

sandbox_create
trap sandbox_destroy EXIT

MARKER='<!-- session-context: slot -->'

if [ ! -r "$TEST_REPO_ROOT/lib/context-budget.sh" ]; then
  fail "S309 — lib/context-budget.sh is missing"
  test_done
fi
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"
case "${CONTEXT_BUDGET_CHARS:-}" in
  ''|*[!0-9]*) fail "S309 — CONTEXT_BUDGET_CHARS is not a number: '${CONTEXT_BUDGET_CHARS:-}'"; test_done ;;
esac
[ "$(printf 'a\xc3\xa9\xe2\x86\x92' | context_chars)" = 3 ] \
  || fail "S309 — context_chars must count UTF-8 code points (a, e-acute, arrow = 3)"

# --- worst-case fixture --------------------------------------------------
long="$(printf 'p%.0s' $(seq 1 100))"
wf="$SANDBOX/clone-$long"
mkdir -p "$wf"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./prep' --exclude='./CLAUDE.md' \
  --exclude='./.claude/settings.json' --exclude='./.claude/skills' --exclude='./.claude/rules' -cf - .) | (cd "$wf" && tar -xf -)
ORCH="$wf/$CORE750_ORCH_REL"
proj="$SANDBOX/project-$long"
mkdir -p "$proj"
git -C "$proj" init -q -b main
ids=()
while IFS='|' read -r id value _; do
  case "$value" in opt-in-loaded:*) ids+=("$id" yes) ;; esac
done < <(. "$wf/lib/changes.sh"; reaches_session_values "$wf/CHANGES.md")
[ "${#ids[@]}" -ge 2 ] || fail "S309 — no CHANGES.md entry declares opt-in-loaded:"
write_adoption "$proj/WORKFLOW-ADOPTION.md" ${ids[@]+"${ids[@]}"} process-multi-agent-roles yes
ln -s "$SANDBOX/nowhere/WORKFLOW.md" "$proj/CLAUDE.md"

# --- wiring: one session-context command, no --slot -----------------------
sc_commands() { # settings.json -> one line per SessionStart command running session-context.sh
  python3 -I - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for g in d.get("hooks", {}).get("SessionStart", []):
    for h in g.get("hooks", []):
        c = h.get("command", "")
        if "session-context.sh" in c:
            print(c.replace("\n", " "))
PY
}
wiring_problems() { # settings.json -> one line per problem
  local n
  n="$(sc_commands "$1" | grep -c .)"
  [ "$n" = 1 ] || echo "SessionStart runs session-context.sh $n times, expected once"
  grep -qF -- '--slot' "$1" && echo "settings still pass --slot"
  return 0
}
p="$(wiring_problems "$wf/settings/session-hooks.json")"
[ -z "$p" ] || fail "S309/wiring — $(tr '\n' ';' <<<"$p")"
# Negative controls: a second command, and a --slot argument, are each caught.
python3 -I - "$wf/settings/session-hooks.json" "$SANDBOX/two.json" "$SANDBOX/slot.json" <<'PY'
import json, sys
src, two, slot = sys.argv[1:4]
for out, extra in ((two, "x/session-context.sh p"), (slot, "x/other.sh --slot 1")):
    d = json.load(open(src))
    for g in d["hooks"]["SessionStart"]:
        if "matcher" not in g:
            g["hooks"].append({"type": "command", "command": extra})
    json.dump(d, open(out, "w"))
PY
grep -q 'times, expected once' <<<"$(wiring_problems "$SANDBOX/two.json")" \
  || fail "S309/neg-wiring — a second session-context command was not caught"
grep -q 'still pass --slot' <<<"$(wiring_problems "$SANDBOX/slot.json")" \
  || fail "S309/neg-wiring — a --slot argument was not caught"

# --slot is gone: rejected as an invalid option, exit 2, nothing on stdout.
for args in "--slot 1" "--slot" "--runtime codex --slot 1"; do
  # shellcheck disable=SC2086 # word splitting of the fixed argument list is intended
  out="$("$wf/session-context.sh" $args "$proj" 2>/dev/null)"; st=$?
  [ "$st" = 2 ] || fail "S309/no-slot — 'session-context.sh $args' exited $st, expected 2"
  [ -z "$out" ] || fail "S309/no-slot — 'session-context.sh $args' printed output"
done

# --- budget and content of the one output ------------------------------------
budget_problem() { # text -> prints the failure when over budget
  local size
  size="$(printf '%s' "$1" | context_chars)"
  [ "$size" -le "$CONTEXT_BUDGET_CHARS" ] || echo "the output is $size characters, over the budget of $CONTEXT_BUDGET_CHARS"
}
content_problems() { # text -> one line per rule-text problem
  printf '%s' "$1" > "$SANDBOX/content.txt"
  core750_rule_hits "$ORCH" "$SANDBOX/content.txt" | sed 's/^\(OR[0-9]*\) .*/rule line \1 printed/'
  grep -q '^# Multi-agent pipeline run rules' "$SANDBOX/content.txt" && echo "a core part heading printed"
  grep -qxF "$MARKER" "$SANDBOX/content.txt" && echo "the marker line printed"
  return 0
}
capture() { # var args... -> the command's stdout, trailing newlines kept
  local __v="$1" o
  shift
  o="$("$@" 2>/dev/null; printf x)"
  printf -v "$__v" '%s' "${o%x}"
}
claude_out='' codex_out=''
capture claude_out "$wf/session-context.sh" "$proj"
capture codex_out "$wf/session-context.sh" --runtime codex "$proj"
check_output() { # runtime text
  local msg
  msg="$(budget_problem "$2")"; [ -z "$msg" ] || fail "S309/budget-$1 — $msg"
  msg="$(content_problems "$2")"; [ -z "$msg" ] || fail "S309/no-rule-text-$1 — $(head -n 3 <<<"$msg" | tr '\n' ';')"
}
check_output claude "$claude_out"
check_output codex "$codex_out"
case "$claude_out" in
  "Warning: CLAUDE.md in $proj is not a link"*) ;;
  *) fail "S309/worst — the Claude output does not start with the CLAUDE.md warning" ;;
esac
[ "$(grep -c '^Warning:' <<<"$claude_out")" -ge 2 ] \
  || fail "S309/worst — the worst case does not print both the CLAUDE.md and the core-link warning"
# Negative controls: over-budget text and a printed rule line are each caught.
over="$(printf 'x%.0s' $(seq 1 $((CONTEXT_BUDGET_CHARS + 1))))"
msg="$(budget_problem "$over")"
case "$msg" in
  *"$((CONTEXT_BUDGET_CHARS + 1))"*"$CONTEXT_BUDGET_CHARS"*) ;;
  *) fail "S309/neg-budget — the failure must name size and budget: '$msg'" ;;
esac
grep -q 'rule line OR10 printed' <<<"$(content_problems "warning
$(grep '^- OR10 ' "$ORCH")")" || fail "S309/neg-content — a printed rule line was not caught"

# --- the docs state the constant -----------------------------------------
doc_number() { # file -> the N of "`CONTEXT_BUDGET_CHARS` (N characters" (commas dropped)
  grep -oE '`CONTEXT_BUDGET_CHARS` \([0-9,]+ characters' "$1" | head -n 1 \
    | sed -E 's/.*\(([0-9,]+) characters/\1/' | tr -d ,
}
for doc in CHANGES.md PRD.md; do
  got="$(doc_number "$wf/$doc")"
  [ "$got" = "$CONTEXT_BUDGET_CHARS" ] \
    || fail "S309/docs — $doc states '${got:-nothing}' for CONTEXT_BUDGET_CHARS, constant is $CONTEXT_BUDGET_CHARS"
done
sed -E 's/`CONTEXT_BUDGET_CHARS` \([0-9,]+ characters/`CONTEXT_BUDGET_CHARS` (8,500 characters/' \
  "$wf/CHANGES.md" > "$SANDBOX/CHANGES.bad"
[ "$(doc_number "$SANDBOX/CHANGES.bad")" = "$CONTEXT_BUDGET_CHARS" ] \
  && fail "S309/neg-docs — a doc number different from the constant passed"

test_done
