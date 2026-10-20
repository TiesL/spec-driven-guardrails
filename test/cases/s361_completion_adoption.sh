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
CLAUDE_PROJECT_DIR="$project" python3 - "$project" <<'PY' || fail "S361 registered hook"
import json,os,subprocess,sys
from pathlib import Path
project=Path(sys.argv[1])
settings=json.loads((project/'.claude/settings.json').read_text())
hooks=[h for group in settings['hooks']['PostToolUse'] if group.get('matcher')=='Bash' for h in group['hooks']]
assert any(h.get('statusMessage')=='push-after-commit' for h in hooks)
hook=next(h for h in hooks if h.get('statusMessage')=='stop-after-completion')
assert not hook.get('async',False)
event=dict(hook_event_name='PostToolUse',tool_name='Bash',cwd=str(project),tool_input=dict(command='gh release create v1'),tool_response=dict(stdout='',stderr='',interrupted=False))
r=subprocess.run(['bash','-c',hook['command']],input=json.dumps(event),text=True,capture_output=True)
assert r.returncode==0 and json.loads(r.stdout)['continue'] is False,(r.stdout,r.stderr)
PY
mkdir -p "$HOME/.codex"
printf '%s\n' 'model = "user-owned-fixture"' > "$HOME/.codex/config.toml"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --runtime codex "$project" >"$SANDBOX/codex.out" 2>&1 || fail "Codex adoption: $(cat "$SANDBOX/codex.out")"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --status --runtime codex "$project" >"$SANDBOX/status" 2>&1 || fail "Codex inventory"
assert_contains "S362 truthful inventory" "runtime-hooks: not-installed" "$(cat "$SANDBOX/status")"
for text in 'save the PR number' 'MERGED' 'distinct tool call' 'durable reporting' '/clear or /new' 'New chat' 'both labeled' 'instruction following'; do
  assert_contains "S362 installed $text" "$text" "$(cat "$project/AGENTS.md")"
done
"$TEST_REPO_ROOT/check-workflow-adapters.sh" || fail "S362 generated artifacts"
[ "$(cat "$HOME/.codex/config.toml")" = 'model = "user-owned-fixture"' ] || fail "S362 user configuration changed"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --runtime codex "$project" >"$SANDBOX/update.out" 2>&1 || fail "Codex update"
assert_contains "S362 update includes completion" 'Completion and fresh context' "$(cat "$project/AGENTS.md")"
echo "S361: wiring only; Claude live loading/termination/reset unverified."
test_done
