#!/usr/bin/env bash
# S65 — Value flags of `gh pr merge` do not shift the target.
# Dekt: F8
#
# Found in pre-merge-review on PR #70: --body/--subject (and the other value
# flags of `gh pr merge`) were skipped as a loose "-*" token, but their value
# token was not — that ended up in the target position (number/url/branch),
# after which `gh pr view "<body-text>"` fails and the guard, via the
# fail-open path, still lets a marker-less PR through.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project waardevlaggen)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

# The fake gh only accepts "pr view --json comments" (no target argument) —
# any other target (such as the text from --body) fails.
fakebin="$(fake_gh_merge_bin "" "")"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge --body \"een tekst met woorden\" --subject titel"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S65 — a marker-less PR with --body/--subject was not blocked (exit $status). Output: $uitvoer"

test_klaar
