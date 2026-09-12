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

opdracht="$(
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
[ -n "$opdracht" ] || fail "S79 — no second SessionStart command found in session-hooks.json"

# Given: a project whose .claude/settings.json points to a vanished checkout
# — the exact state after a repo rename before re-adoption.
project="$(fresh_project verweesd)"
mkdir -p "$project/.claude"
verdwenen="$SANDBOX/checkout-die-niet-meer-bestaat"
mkdir -p "$verdwenen/settings"
ln -s "$verdwenen/settings/session-hooks.json" "$project/.claude/settings.json"
rm -rf "$verdwenen"

# When: session start runs the command.
uitvoer="$(cd "$project" && bash -c "$opdracht" 2>&1)"
status=$?

# Then: this reports itself, and the session does not start silently without hooks.
[ "$status" -eq 0 ] || fail "S79 — the command failed (exit $status) instead of reporting cleanly and continuing"
printf '%s' "$uitvoer" | grep -qi 'niet bestaat' \
  || fail "S79 — no message about the missing directory. Output: $uitvoer"
printf '%s' "$uitvoer" | grep -qi 'adopt.sh opnieuw' \
  || fail "S79 — the message does not say what to do about it. Output: $uitvoer"

# --- Regression: a healthy symlink stays silent (no false alarms) and
# lets pending-changes.sh run normally.
project_gezond="$(fresh_project gezond)"
mkdir -p "$project_gezond/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project_gezond/.claude/settings.json"
uitvoer_gezond="$(cd "$project_gezond" && bash -c "$opdracht" 2>&1)"
printf '%s' "$uitvoer_gezond" | grep -qi 'niet bestaat' \
  && fail "S79 — false alarm for a healthy symlink. Output: $uitvoer_gezond"

# --- Regression: no .claude/settings.json (non-adopted project) stays
# silent — no message, no error status.
project_kaal="$(fresh_project kaal)"
uitvoer_kaal="$(cd "$project_kaal" && bash -c "$opdracht" 2>&1)"
status_kaal=$?
[ "$status_kaal" -eq 0 ] || fail "S79 — a non-adopted project gave an error status"
[ -z "$uitvoer_kaal" ] || fail "S79 — a non-adopted project gave unexpected output: $uitvoer_kaal"

test_done
