#!/usr/bin/env bash
# S56 — A successful commit is pushed immediately.
# Covers: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

hook="$TEST_REPO_ROOT/hooks/push-after-commit"
[ -x "$hook" ] || { fail "S56 — hooks/push-after-commit is missing or not executable"; test_done; }

project="$(fresh_project with-remote)"
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" push -q -u origin main
git -C "$project" checkout -q -b feature/work

# Given: a feature branch with a new commit.
git -C "$project" commit -q --allow-empty -m "nieuw werk"
lokale_sha="$(git -C "$project" rev-parse HEAD)"

# When: the PostToolUse hook runs after that commit.
input='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git commit -m \"nieuw werk\""},"tool_response":{"type":"text","text":"[main abc1234] nieuw werk"}}'
printf '%s' "$input" | "$hook" >/dev/null 2>&1

# Then: the current branch is on origin.
remote_sha="$(git -C "$remote" rev-parse feature/work 2>/dev/null)"
[ "$remote_sha" = "$lokale_sha" ] || fail "S56 — feature/work is not on the remote (or not up to date) after the commit"

test_done
