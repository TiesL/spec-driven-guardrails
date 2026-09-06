#!/usr/bin/env bash
# T4 — CI-check "PR verwijst naar issue" (schakel 3, hard slot).
# Dekt: F13
#
# templates/check-pr-issue-link.sh beoordeelt uitsluitend de PR die de CI-run
# triggert (W19b) — geen audit over de geschiedenis, dat zou eeuwig blijven
# falen op de 27 issueloze PR's van vóór dit werkitem.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-pr-issue-link.sh"
[ -x "$script" ] || { fail "T4 — templates/check-pr-issue-link.sh ontbreekt of is niet uitvoerbaar"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

fixtures="$SANDBOX/fixtures"
mkdir -p "$fixtures"

fakebin="$(fake_gh_bin '
nummer="$3"
bestand="'"$fixtures"'/$nummer"
if [ -f "$bestand" ]; then
  cat "$bestand"
  exit 0
fi
exit 1
')"

# AC2 — PR zonder gelinkt issue faalt, met het PR-nummer in de melding.
echo 0 > "$fixtures/42"
uitvoer="$(PATH="$fakebin:$PATH" "$script" 42 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4/AC2 — PR zonder gelinkt issue gaf exit 0"
assert_contains "T4/AC2 — het PR-nummer staat in de melding" "42" "$uitvoer"

# AC3 — PR met gelinkt issue slaagt.
echo 1 > "$fixtures/43"
uitvoer="$(PATH="$fakebin:$PATH" "$script" 43 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC3 — PR met gelinkt issue gaf exit $status: $uitvoer"

# AC4 — alleen de huidige PR wordt beoordeeld: PR 42 (issueloos, hierboven al
# gecontroleerd) staat nog steeds zo in de fixtures, en een aanroep voor PR 43
# raakt daar niet aan.
uitvoer="$(PATH="$fakebin:$PATH" "$script" 43 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC4 — de eerdere PR 42 beïnvloedde de beoordeling van PR 43"

test_klaar
