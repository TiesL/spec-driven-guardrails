#!/usr/bin/env bash
# S52, S53, S59 — CI detecteert commits op main die niet uit een PR komen.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-main-via-pr.sh"
[ -x "$script" ] || { fail "S52 — templates/check-main-via-pr.sh ontbreekt of is niet uitvoerbaar"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

fakebin="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/commits/zonder-pr/pulls --jq length")
    echo 0; exit 0 ;;
  "api repos/{owner}/{repo}/commits/met-pr/pulls --jq length")
    echo 1; exit 0 ;;
  "api repos/{owner}/{repo}/commits/onbekend/pulls --jq length")
    exit 1 ;;
esac
exit 1
')"

# S52 — een commit zonder PR wordt gemeld, met de commit in de melding.
uitvoer="$(PATH="$fakebin:$PATH" "$script" zonder-pr 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S52 — een commit zonder PR gaf exit 0"
assert_contains "S52 — de melding noemt de commit" "zonder-pr" "$uitvoer"

# S52 — een merge-commit die wél uit een PR komt, laat door.
uitvoer="$(PATH="$fakebin:$PATH" "$script" met-pr 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S52 — een commit mét PR gaf exit $status: $uitvoer"

# S53 — de controle kijkt niet naar historie: elke aanroep beoordeelt precies
# de meegegeven SHA, niets ervoor of erna. Aangetoond doordat "zonder-pr" en
# "met-pr" onafhankelijk hun eigen, juiste uitkomst geven ongeacht volgorde.
uitvoer="$(PATH="$fakebin:$PATH" "$script" met-pr 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S53 — de tweede aanroep voor met-pr week af van de eerste"

# S59 — kan de herkomst niet worden vastgesteld, dan faalt de controle, met
# de reden erbij. Bewust het omgekeerde van de lokale git-hooks (S58).
uitvoer="$(PATH="$fakebin:$PATH" "$script" onbekend 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S59 — een onbekende herkomst gaf exit 0 (moet falen, geen faal-open)"
assert_contains "S59 — de melding noemt dat de herkomst niet vastgesteld kon worden" "couldn't establish" "$uitvoer"

# S59 — ook zonder gh faalt de controle (geen faal-open, in tegenstelling tot
# de lokale hooks).
padzondergh="$(pad_zonder_gh)"
uitvoer="$(PATH="$padzondergh" "$script" zonder-pr 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S59 — zonder gh gaf de controle exit 0 in plaats van te falen"

test_klaar
