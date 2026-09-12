#!/usr/bin/env bash
# S44 — The hook wiring lets the block through.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project whose .claude/settings.json symlinks to this repo.
project="$(fresh_project wired)"
mkdir -p "$project/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project/.claude/settings.json"

command="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hooks.PreToolUse[0].hooks[0].command' "$TEST_REPO_ROOT/settings/session-hooks.json"
  else
    python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]
print(h["command"])
' "$TEST_REPO_ROOT/settings/session-hooks.json"
  fi
)"

if [ -z "$command" ]; then
  fail "S44 — no PreToolUse command found in session-hooks.json"
  test_done
fi

input='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git reset --hard"}}'

# When/Then: the wiring produces exit 2 — the block really comes through.
printf '%s' "$input" | (cd "$project" && bash -c "$command") >/dev/null 2>&1
status=$?
[ "$status" -eq 2 ] || fail "S44 — the wiring returned $status instead of 2; the guard does not block"

# And: the form with && and || does not do that. This check exists so that
# form never sneaks back in: it looks like it works, but the || catches exit 2
# and reports success.
wrong_form='wf=$(dirname "$(dirname "$(readlink .claude/settings.json 2>/dev/null)")") && [ -x "$wf/hooks/git-guardrails" ] && "$wf/hooks/git-guardrails" || exit 0'
printf '%s' "$input" | (cd "$project" && bash -c "$wrong_form") >/dev/null 2>&1
if [ $? -eq 2 ]; then
  fail "S44 — the assumption no longer holds: the &&/|| form does let exit 2 through"
fi

# And the configured command therefore does not use that form.
case "$command" in
  *'|| exit 0'*) fail "S44 — the hook command uses the form that swallows exit 2" ;;
esac
case "$command" in
  *'exec '*) ;;
  *) fail "S44 — the hook command does not use exec; the exit status does not then come through" ;;
esac

# And: the wiring must not depend on the incidental working directory of the
# hook process. If it runs in a subdirectory, a relative `readlink` would find
# nothing and the guard would silently fail - without any message, unlike the
# loud failure on missing jq/python3.
mkdir -p "$project/src/diep"
printf '%s' "$input" | (cd "$project/src/diep" && CLAUDE_PROJECT_DIR="$project" bash -c "$command") >/dev/null 2>&1
status_deep=$?
[ "$status_deep" -eq 2 ] || fail "S44 — the wiring fails from a subdirectory (exit $status_deep)"

# Legitimate work must also get through the wiring.
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work
ok='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git push origin HEAD"}}'
printf '%s' "$ok" | (cd "$project" && bash -c "$command") >/dev/null 2>&1
[ $? -ne 2 ] || fail "S44 — the wiring blocks a legitimate push"

test_done
