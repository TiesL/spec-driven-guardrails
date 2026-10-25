#!/usr/bin/env bash
# S361-S362 — real Claude settings and generated/adopted Codex instructions.
# Covers: F56
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
project="$(fresh_project completion)"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project" >"$SANDBOX/adopt.out" 2>&1 || fail "Claude adoption: $(cat "$SANDBOX/adopt.out")"
mkdir -p "$SANDBOX/fakebin"
printf '%s\n' '#!/bin/sh' "echo '{\"baseRefName\":\"main\",\"state\":\"MERGED\"}'" > "$SANDBOX/fakebin/gh"
chmod +x "$SANDBOX/fakebin/gh"
PATH="$SANDBOX/fakebin:$PATH" CLAUDE_PROJECT_DIR="$project" python3 - "$project" <<'PY' || fail "S361 registered hook"
import json,os,subprocess,sys
from pathlib import Path
project=Path(sys.argv[1])
settings=json.loads((project/'.claude/settings.json').read_text())
hooks=[h for group in settings['hooks']['PostToolUse'] if group.get('matcher')=='Bash' for h in group['hooks']]
assert any(h.get('statusMessage')=='push-after-commit' for h in hooks)
hook=next(h for h in hooks if h.get('statusMessage')=='stop-after-completion')
assert not hook.get('async',False)
event=dict(hook_event_name='PostToolUse',tool_name='Bash',cwd=str(project),tool_input=dict(command='gh pr merge 500'),tool_response=dict(stdout='',stderr='',interrupted=False))
r=subprocess.run(['bash','-c',hook['command']],input=json.dumps(event),text=True,capture_output=True)
assert r.returncode==0 and r.stdout.strip(),(r.stdout,r.stderr)
out=json.loads(r.stdout)
assert out=={'systemMessage':'Merged to main. Type /clear before the next work item; if you are tagging a release, tag it first.'} and 'continue' not in out and 'stopReason' not in out,(r.stdout,r.stderr)
PY
mkdir -p "$HOME/.codex"
printf '%s\n' 'model = "user-owned-fixture"' > "$HOME/.codex/config.toml"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --runtime codex "$project" >"$SANDBOX/codex.out" 2>&1 || fail "Codex adoption: $(cat "$SANDBOX/codex.out")"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --status --runtime codex "$project" >"$SANDBOX/status" 2>&1 || fail "Codex inventory"
assert_contains "S362 truthful inventory" "runtime-hooks: not-installed" "$(cat "$SANDBOX/status")"
for text in 'save the PR number' 'MERGED' 'durable reporting' '/clear or /new' 'New chat' 'both labeled' 'instruction following'; do
  assert_contains "S362 installed $text" "$text" "$(cat "$project/AGENTS.md")"
done
"$TEST_REPO_ROOT/check-workflow-adapters.sh" || fail "S362 generated artifacts"
python3 - "$TEST_REPO_ROOT" "$project" <<'PY' || fail "S362 decision-8 wording"
import re,sys
from pathlib import Path
root,project=map(Path,sys.argv[1:])
def text(p): return re.sub(r'\s+',' ',(p).read_text())
note='if you are tagging a release, tag it first.'
cli='Merged to main. Use /clear or /new before the next work item; '+note
desktop='Merged to main. Start a New chat before the next work item; '+note
claude='Merged to main. Type /clear before the next work item; '+note
agents=text(project/'AGENTS.md')
assert cli in agents and desktop in agents, 'Codex CLI/desktop tag-note wording'
assert cli in text(root/'adapters/codex/AGENTS.md') and desktop in text(root/'adapters/codex/INSTRUCTIONS.md')
assert claude in text(root/'adapters/claude/INSTRUCTIONS.md'), 'Claude adapter quotes the hook reminder'
step5='gh pr merge <n> --squash --delete-branch'
for rel in ['policy/WORKFLOW.md','WORKFLOW.md','adapters/codex/AGENTS.md']:
    assert step5 in text(root/rel), rel+' step 5 names the PR'
assert step5 in agents
gone=['tag published','sole continuation','approved tag next','approved release tag','independently published tags','local for tags','continue: false','distinct tool call','only the final result','end the turn','ends the turn','finish the turn','ends the current turn']
for rel in ['policy/WORKFLOW.md','adapters/codex/INSTRUCTIONS.md','adapters/codex/AGENTS.md','adapters/claude/INSTRUCTIONS.md','WORKFLOW.md','skills/release-branch-workflow/SKILL.md','README.md','CHANGELOG.md']:
    body=text(root/rel).lower()
    for phrase in gone: assert phrase not in body, (rel,phrase)
for phrase in gone: assert phrase not in agents.lower(), ('project AGENTS.md',phrase)
PY
[ "$(cat "$HOME/.codex/config.toml")" = 'model = "user-owned-fixture"' ] || fail "S362 user configuration changed"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --runtime codex "$project" >"$SANDBOX/update.out" 2>&1 || fail "Codex update"
assert_contains "S362 update includes completion" 'Completion and fresh context' "$(cat "$project/AGENTS.md")"
echo "S361: wiring only; Claude live loading, display of the systemMessage and reset unverified."
test_done
