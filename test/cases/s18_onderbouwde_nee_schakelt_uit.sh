#!/usr/bin/env bash
# S18 — Een onderbouwde `nee` schakelt de merge-guard uit, zonder netwerkaanroep.
# Dekt: F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project uitgeschakeld)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

cat > "$project/WORKFLOW-ADOPTIE.md" <<EOF
# Adoptie van gedeelde workflow-wijzigingen

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| kwaliteitsreview-voor-merge | nee | 2026-01-01 | dit project heeft geen PR's, alleen directe commits door één persoon |
EOF

# Zou de guard gh toch aanroepen, dan verraadt dit bestand dat.
sentinel="$SANDBOX/gh-was-aangeroepen"
fakebin="$(fake_gh_bin '
touch "'"$sentinel"'"
exit 1
')"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S18 — verwacht doorgang (exit 0), kreeg $status. Uitvoer: $uitvoer"
[ ! -e "$sentinel" ] || fail "S18 — de guard riep gh aan terwijl de rij op 'nee' staat; dat hoort lokaal te blijven"

test_klaar
