#!/usr/bin/env bash
# S56 — Een geslaagde commit is meteen gepusht.
# Dekt: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

hook="$TEST_REPO_ROOT/hooks/push-na-commit"
[ -x "$hook" ] || { fail "S56 — hooks/push-na-commit ontbreekt of is niet uitvoerbaar"; test_klaar; }

project="$(vers_project met-remote)"
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" push -q -u origin main
git -C "$project" checkout -q -b feature/werk

# Given: een feature-branch met een nieuwe commit.
git -C "$project" commit -q --allow-empty -m "nieuw werk"
lokale_sha="$(git -C "$project" rev-parse HEAD)"

# When: de PostToolUse-hook draait na die commit.
invoer='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git commit -m \"nieuw werk\""},"tool_response":{"type":"text","text":"[main abc1234] nieuw werk"}}'
printf '%s' "$invoer" | "$hook" >/dev/null 2>&1

# Then: de huidige branch staat op origin.
remote_sha="$(git -C "$remote" rev-parse feature/werk 2>/dev/null)"
[ "$remote_sha" = "$lokale_sha" ] || fail "S56 — feature/werk staat niet (of niet up-to-date) op de remote na de commit"

test_klaar
