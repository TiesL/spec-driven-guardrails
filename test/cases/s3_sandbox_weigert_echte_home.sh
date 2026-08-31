#!/usr/bin/env bash
# S3 — De testsandbox weigert te draaien met de echte HOME.
# Dekt: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Given: een test waarvan de sandboxopzet HOME niet heeft omgezet.
# When/Then: de guard weigert, met een expliciete melding.
uitvoer="$(HOME="$TEST_REAL_HOME" sandbox_guard 2>&1)"
status=$?

if [ "$status" -eq 0 ]; then
  fail "S3 — sandbox_guard liet de echte HOME passeren"
fi
assert_contains "S3" "AFGEBROKEN" "$uitvoer"
assert_contains "S3" "echte home" "$uitvoer"

# En een lege HOME is net zo goed geen sandbox.
uitvoer_leeg="$(HOME="" sandbox_guard 2>&1)"
status_leeg=$?
if [ "$status_leeg" -eq 0 ]; then
  fail "S3 — sandbox_guard liet een lege HOME passeren"
fi
assert_contains "S3 (lege HOME)" "AFGEBROKEN" "$uitvoer_leeg"

# And: er is niets geschreven buiten de tijdelijke map. De guard draait vóór
# elke schrijfactie, dus een geweigerde opzet laat geen sporen na.
sandbox_create
trap sandbox_destroy EXIT
if [ "$HOME" = "$TEST_REAL_HOME" ]; then
  fail "S3 — sandbox_create heeft HOME niet omgezet"
fi
case "$HOME" in
  "$SANDBOX"*) ;;
  *) fail "S3 — HOME wijst niet in de sandbox: $HOME" ;;
esac

# De And-clausule werd tot nu toe afgeleid uit de controlestroom in plaats van
# aangetoond. Een canary bewijst het: schrijf naar $HOME en stel vast dat het
# bestand in de sandbox belandt en niet in de echte home. De controle op de
# echte home is puur lezend - we schrijven daar per definitie niet.
canary="canary-$$-$(date +%s)"
echo "sandbox" > "$HOME/$canary"

if [ ! -e "$SANDBOX/home/$canary" ]; then
  fail "S3 — schrijfactie naar \$HOME belandde niet in de sandbox"
fi
if [ -e "$TEST_REAL_HOME/$canary" ]; then
  fail "S3 — er is geschreven in de echte home ($TEST_REAL_HOME/$canary)"
fi

test_klaar
