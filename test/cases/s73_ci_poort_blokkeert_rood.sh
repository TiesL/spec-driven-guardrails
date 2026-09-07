#!/usr/bin/env bash
# S73 — De merge-guard blokkeert `gh pr merge` als CI niet groen is.
# Dekt: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project ci-rood)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"bevindingen\\n<!-- pre-merge-review:done -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    printf "%s" "[{\"name\":\"check\",\"bucket\":\"fail\"}]"
    exit 0 ;;
esac
exit 1
')"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S73 — verwacht blokkade (exit 2) bij falende CI, kreeg $status. Uitvoer: $uitvoer"
assert_contains "S73 — de melding noemt de falende check" "check: fail" "$uitvoer"

test_klaar
