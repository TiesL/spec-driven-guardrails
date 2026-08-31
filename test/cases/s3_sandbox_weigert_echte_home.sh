#!/usr/bin/env bash
# S3 — De testsandbox weigert te draaien met de echte HOME.
# Dekt: F1

set -uo pipefail
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

test_klaar
