#!/usr/bin/env bash
# S79 — A .claude/settings.json pointing to a non-existent directory (e.g.
# after a rename like W32/#56, before re-adoption) reports itself loudly at
# session start, instead of silently running no hooks.
# Covers: W32 AC3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

command="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hooks.SessionStart[0].hooks[1].command' "$TEST_REPO_ROOT/settings/session-hooks.json"
  else
    python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][1]
print(h["command"])
' "$TEST_REPO_ROOT/settings/session-hooks.json"
  fi
)"
[ -n "$command" ] || fail "S79 — no second SessionStart command found in session-hooks.json"

# Given: a project whose .claude/settings.json points to a vanished checkout
# — the exact state after a repo rename before re-adoption.
project="$(fresh_project orphaned)"
mkdir -p "$project/.claude"
disappeared="$SANDBOX/vanished-checkout"
mkdir -p "$disappeared/settings"
ln -s "$disappeared/settings/session-hooks.json" "$project/.claude/settings.json"
rm -rf "$disappeared"

# When: session start runs the command.
output="$(cd "$project" && bash -c "$command" 2>&1)"
status=$?

# Then: this reports itself, and the session does not start silently without hooks.
[ "$status" -eq 0 ] || fail "S79 — the command failed (exit $status) instead of reporting cleanly and continuing"
printf '%s' "$output" | grep -qi "doesn't exist" \
  || fail "S79 — no message about the missing directory. Output: $output"
printf '%s' "$output" | grep -qi 'adopt.sh again' \
  || fail "S79 — the message does not say what to do about it. Output: $output"

# --- Regression: a healthy symlink stays silent (no false alarms) and
# lets pending-changes.sh run normally.
project_healthy="$(fresh_project healthy)"
mkdir -p "$project_healthy/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project_healthy/.claude/settings.json"
output_healthy="$(cd "$project_healthy" && bash -c "$command" 2>&1)"
printf '%s' "$output_healthy" | grep -qi "doesn't exist" \
  && fail "S79 — false alarm for a healthy symlink. Output: $output_healthy"

# --- Regression: no .claude/settings.json (non-adopted project) stays
# silent — no message, no error status.
project_bare="$(fresh_project bare)"
output_bare="$(cd "$project_bare" && bash -c "$command" 2>&1)"
status_bare=$?
[ "$status_bare" -eq 0 ] || fail "S79 — a non-adopted project gave an error status"
[ -z "$output_bare" ] || fail "S79 — a non-adopted project gave unexpected output: $output_bare"

test_done
