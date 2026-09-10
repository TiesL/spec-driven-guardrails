#!/usr/bin/env bash
# S17 — The merge guard fails open without gh or without network.
# Dekt: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project geen-netwerk)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'

# Sub-case a: gh is missing entirely.
padzondergh="$(pad_zonder_gh)"
uitvoer_a="$(printf '%s' "$invoer" | PATH="$padzondergh" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status_a=$?
[ "$status_a" -ne 2 ] || fail "S17a — gh is missing, but the command was blocked anyway"
assert_contains "S17a" "warning" "$uitvoer_a"

# Sub-case b: gh is present, but the network is not — the call fails.
fakebin="$(fake_gh_bin '
exit 1
')"
uitvoer_b="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status_b=$?
[ "$status_b" -ne 2 ] || fail "S17b — gh fails (no network), but the command was blocked anyway"
assert_contains "S17b" "warning" "$uitvoer_b"

test_klaar
