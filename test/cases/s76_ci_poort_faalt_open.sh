#!/usr/bin/env bash
# S76 — De CI-poort faalt open als de CI-opvraging zelf mislukt.
# Dekt: F8
#
# De review-marker is aanwezig (dus de eerste controle slaagt); de CI-check
# zelf faalt (geen netwerk, gh-fout, wat dan ook). Dezelfde grondregel als
# overal in deze guard: de controle is nooit het commando dat vastloopt.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project ci-query-faalt)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"bevindingen\\n<!-- pre-merge-review:done -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    exit 1 ;;
esac
exit 1
')"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S76 — verwacht doorgang (exit 0) als de CI-opvraging faalt, kreeg $status. Uitvoer: $uitvoer"
assert_contains "S76 — luide waarschuwing over de overgeslagen CI-controle" "warning" "$uitvoer"

test_klaar
