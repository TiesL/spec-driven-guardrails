#!/usr/bin/env bash
# S178 — The SessionStart hook chain delivers the orchestrator rules to an
# opted-in project, reaches it without re-adoption, and warns when CLAUDE.md
# is not linked.
# Covers: F37
#
# Issue #371, A16, AC1/AC3/AC11. Seam: the SessionStart commands exactly as
# a project's .claude/settings.json symlink exposes them, run the way Claude
# Code runs them (CLAUDE_PROJECT_DIR set, one shell each), against a real
# adoption from a copy of this clone. Whether a session then ACTS on the
# text is model behaviour and not testable here (see S180).

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

# 1. Opted in: the combined hook output carries ORCHESTRATOR.md.
yes_p="$(adopt_from_copy yes)"
write_adoption "$yes_p/WORKFLOW-ADOPTION.md" "$id" yes
out="$(run_session_start "$yes_p")"
output_has_all_lines "$orch" "$out" \
  || fail "S178/1 — an opted-in project's SessionStart output does not carry all of ORCHESTRATOR.md"

# 2. Updates propagate without re-adoption and without re-answering (AC11):
# the clone ships a later ORCHESTRATOR.md, the project is not touched.
printf 'PROPAGATION-SENTINEL-371 shipped in a later release\n' >> "$orch"
out="$(run_session_start "$yes_p")"
assert_contains "S178/2 — a later ORCHESTRATOR.md reaches the project's next session" "PROPAGATION-SENTINEL-371" "$out"
# restore for the next cases
sed -i.bak '/PROPAGATION-SENTINEL-371/d' "$orch" && rm -f "$orch.bak"

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

# 6. The orchestrator text is injected whatever the missing link: the
# warning is additional, not a replacement.
rm -f "$yes_p/CLAUDE.md"
out="$(run_session_start "$yes_p")"
output_has_all_lines "$orch" "$out" \
  || fail "S178/6 — with CLAUDE.md missing, the orchestrator text was no longer delivered"

# 7. Wiring: the hook resolves the clone by readlink like the pending-changes
# command (no per-project copy, no hard-coded path), so no re-adoption is
# ever needed to pick up a change.
settings="$TEST_REPO_ROOT/settings/session-hooks.json"
cmds="$(session_start_commands "$settings")"
session_cmd="$(grep 'session-context.sh' <<<"$cmds")"
if [ -z "$session_cmd" ]; then
  fail "S178/7 — no SessionStart command calls session-context.sh"
else
  case "$session_cmd" in
    *'readlink'*) ;;
    *) fail "S178/7 — the session-context command does not resolve the clone through readlink" ;;
  esac
  case "$session_cmd" in
    */Users/*|*/home/*|*SPEC_DRIVEN_GUARDRAILS_DIR*) fail "S178/7 — the session-context command hard-codes a path or relies on an env var" ;;
  esac
fi

test_done
