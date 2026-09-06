#!/usr/bin/env bash
# S65 — Waardevlaggen van `gh pr merge` schuiven het doel niet op.
# Dekt: F8
#
# Gevonden in pre-merge-review op PR #70: --body/--subject (en de andere
# waardevlaggen van `gh pr merge`) werden als los "-*"-token overgeslagen,
# maar hun waarde-token niet — die kwam zo op de doelpositie
# (nummer/url/branch) terecht, waarna `gh pr view "<lichaamstekst>"` faalt en
# de guard via het faal-openpad een marker-loze PR alsnog doorlaat.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project waardevlaggen)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

# De nep-gh accepteert alleen "pr view --json comments" (geen doelargument) —
# elk ander doel (zoals de tekst uit --body) faalt.
fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    echo "{\"comments\":[{\"body\":\"geen marker hier\"}]}"
    exit 0 ;;
esac
exit 1
')"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge --body \"een tekst met woorden\" --subject titel"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 2 ] || fail "S65 — een marker-loze PR met --body/--subject werd niet geblokkeerd (exit $status). Uitvoer: $uitvoer"

test_klaar
