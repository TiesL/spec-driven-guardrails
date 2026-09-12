#!/usr/bin/env bash
# S13 — Push to a feature branch keeps working.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S13 — hooks/git-guardrails is missing"; test_klaar; }

project="$(vers_project werk)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

# The SessionEnd hook runs exactly this command when ending every
# session. If the guard blocks that, it breaks the existing provision.
sessie_einde="$(grep -o 'git push origin HEAD' "$TEST_REPO_ROOT/settings/session-hooks.json" | head -1)"
[ -n "$sessie_einde" ] || fail "S13 — the SessionEnd hook no longer pushes with 'git push origin HEAD'; update the test"

printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git push origin HEAD"}}' \
  "$project" | "$guard" >/dev/null 2>&1
status=$?
[ "$status" -ne 2 ] || fail "S13 — the guard blocks the push from the SessionEnd hook"

# Tools other than Bash do not go past this guard anyway, but if they
# did, it should let them through rather than guess.
printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"/x","old_string":"git push origin main","new_string":"y"}}' \
  "$project" | "$guard" >/dev/null 2>&1
[ $? -ne 2 ] || fail "S13 — the guard blocks a non-Bash tool"

test_klaar
