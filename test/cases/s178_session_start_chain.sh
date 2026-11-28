#!/usr/bin/env bash
# S178 — The one SessionStart command carries no orchestrator rule text,
# keeps the pending-changes report, and warns when CLAUDE.md is not linked.
# Covers: F38
#
# Issue #371, A16, AC1/AC3; amended by #750 (A66 D2): the core reaches an
# opted-in session through the always-loaded link (S732), which also owns
# "a release arrives without re-adoption". Seam: the SessionStart commands
# exactly as a project's .claude/settings.json symlink exposes them, run the
# way Claude Code runs them (CLAUDE_PROJECT_DIR set, one shell each), against
# a real adoption from a copy of this clone.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"
wf="$(sandbox_copy_repo wf)"
orch="$wf/skills/role-contracts/ORCHESTRATOR.md"
if [ ! -f "$orch" ]; then
  fail "S178 — skills/role-contracts/ORCHESTRATOR.md does not exist"
  test_done
fi

adopt_from_copy() {
  local p
  p="$(fresh_project "$1")"
  SPEC_DRIVEN_GUARDRAILS_DIR="$wf" "$wf/adopt.sh" "$p" >/dev/null 2>&1
  echo "$p"
}

# 1. Opted in: the hook output carries no ORCHESTRATOR.md rule text (the
# core is the always-loaded file now, not hook output).
yes_p="$(adopt_from_copy yes)"
write_adoption "$yes_p/WORKFLOW-ADOPTION.md" "$id" yes
out="$(run_session_start "$yes_p")"
output_has_any_line "$orch" "$out" \
  && fail "S178/1 — an opted-in project's SessionStart output still carries ORCHESTRATOR.md text"

# 3. Row answered no: no orchestrator text.
no_p="$(adopt_from_copy no)"
write_adoption "$no_p/WORKFLOW-ADOPTION.md" "$id" no
out="$(run_session_start "$no_p")"
output_has_any_line "$orch" "$out" && fail "S178/3 — a no row still got orchestrator text at session start"

# 4. Row never answered: no orchestrator text; the existing pending-changes
# report still names the row (nothing nags beyond it).
un_p="$(adopt_from_copy unanswered)"
out="$(run_session_start "$un_p")"
output_has_any_line "$orch" "$out" && fail "S178/4 — an unanswered row got orchestrator text at session start"
assert_contains "S178/4 — pending-changes still reports the unanswered row" "$id" "$out"

# 5. CLAUDE.md drift warning (F1): fires when the link is missing or does
# not point at the clone's WORKFLOW.md; silent when it is right.
out="$(run_session_start "$no_p")"
case "$out" in
  *CLAUDE.md*) fail "S178/5 — a correct CLAUDE.md link still produced a CLAUDE.md warning: $out" ;;
esac
rm -f "$no_p/CLAUDE.md"
out="$(run_session_start "$no_p")"
assert_contains "S178/5 — missing CLAUDE.md link: warning names CLAUDE.md" "CLAUDE.md" "$out"
assert_contains "S178/5 — missing CLAUDE.md link: warning says to run adopt.sh" "adopt.sh" "$out"
printf 'my own notes\n' > "$no_p/CLAUDE.md"
out="$(run_session_start "$no_p")"
assert_contains "S178/5 — CLAUDE.md is a regular file, not the link" "CLAUDE.md" "$out"
rm -f "$no_p/CLAUDE.md"
ln -s "$SANDBOX/elsewhere.md" "$no_p/CLAUDE.md"
out="$(run_session_start "$no_p")"
assert_contains "S178/5 — CLAUDE.md links to the wrong file" "CLAUDE.md" "$out"

# 6. Opted in with CLAUDE.md missing: the CLAUDE.md warning, still no
# orchestrator text.
rm -f "$yes_p/CLAUDE.md"
out="$(run_session_start "$yes_p")"
assert_contains "S178/6 — opted in, CLAUDE.md missing: warning names CLAUDE.md" "CLAUDE.md" "$out"
output_has_any_line "$orch" "$out" \
  && fail "S178/6 — with CLAUDE.md missing, the SessionStart output carries ORCHESTRATOR.md text"

# 7. Wiring: exactly one command calls session-context.sh, and it resolves
# the clone by readlink like the pending-changes command (no per-project
# copy, no hard-coded path).
settings="$TEST_REPO_ROOT/settings/session-hooks.json"
cmds="$(session_start_commands "$settings")"
session_cmd="$(grep 'session-context.sh' <<<"$cmds")"
if [ -z "$session_cmd" ]; then
  fail "S178/7 — no SessionStart command calls session-context.sh"
elif [ "$(grep -c . <<<"$session_cmd")" -ne 1 ]; then
  fail "S178/7 — more than one SessionStart command calls session-context.sh"
else
  case "$session_cmd" in
    *'readlink'*) ;;
    *) fail "S178/7 — the session-context command does not resolve the clone through readlink" ;;
  esac
  case "$session_cmd" in
    *CLAUDE.md*) fail "S178/7 — the CLAUDE.md warning must live in session-context.sh, not in the hook JSON" ;;
  esac
  case "$session_cmd" in
    */Users/*|*/home/*|*SPEC_DRIVEN_GUARDRAILS_DIR*) fail "S178/7 — the session-context command hard-codes a path or relies on an env var" ;;
  esac
fi

test_done
