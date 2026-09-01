#!/usr/bin/env bash
# S36 — Een ID in de toelichting telt niet als antwoord.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project met-toelichting)"
adopteer "$project"

# test-integratie heeft `Standaard: vraag` en wordt dus nooit geseed: hij staat
# na een verse adoptie open. Dat is de controlewaarde.
voor="$SANDBOX/voor.txt"
openstaande_ids "$project" > "$voor"
grep -qx 'test-integratie' "$voor" || {
  fail "S36 — test-integratie stond niet open na verse adoptie; opzet deugt niet"
  test_klaar
}

# Given: het ID komt voor in de vrije toelichtingstekst van een andere rij.
printf '| proces-prd | ja | 2026-01-01 | nog geen test-integratie afgesproken |\n' \
  >> "$project/WORKFLOW-ADOPTIE.md"

# When/Then: de wijziging staat nog steeds open - alleen de ID-kolom telt.
na="$SANDBOX/na.txt"
openstaande_ids "$project" > "$na"

if ! grep -qx 'test-integratie' "$na"; then
  fail "S36 — test-integratie verdween door een vermelding in de toelichting"
fi

test_klaar
