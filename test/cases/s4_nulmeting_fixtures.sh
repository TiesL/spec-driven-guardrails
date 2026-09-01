#!/usr/bin/env bash
# S4 — Nulmeting-fixture legt `a2t-emails` vast zoals gevonden.
# Dekt: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"

# De viervoudige vergelijking van gouden sets zit in R9
# (r9_nulmeting_onveranderd.sh). Dit scenario gaat specifiek over de vraag of
# a2t-emails is vastgelegd zoals gevonden, zonder reparatie.

# a2t-emails is het bijzondere geval: geen WORKFLOW-ADOPTIE.md, dus alles staat
# open. Vastleggen zoals gevonden - niet eerst repareren, anders legt de fixture
# de reparatie vast in plaats van de toestand.
a2t="$nulmeting/a2t-emails"

if [ -e "$a2t/WORKFLOW-ADOPTIE.md" ]; then
  fail "S4 — de a2t-emails-fixture heeft een WORKFLOW-ADOPTIE.md; die hoort er niet te zijn"
fi

# Niet-circulaire controle dat er niets vooraf beantwoord is: ci-conventie is in
# tennis-admin wél beantwoord. Staat hij hier open, dan is de fixture ongerepareerd.
# Geen `if [ -f ... ]`-guard: ontbreekt de gouden set, dan is dat een fout en
# geen reden om stilzwijgend niets te controleren.
if [ ! -f "$a2t/verwacht-openstaand.txt" ]; then
  fail "S4 — gouden set van a2t-emails ontbreekt"
  test_klaar
fi

if ! grep -qx 'ci-conventie' "$a2t/verwacht-openstaand.txt"; then
  fail "S4 — ci-conventie ontbreekt in de a2t-nulmeting; lijkt vooraf beantwoord"
fi
aantal="$(grep -c . "$a2t/verwacht-openstaand.txt")"
if [ "$aantal" -lt 20 ]; then
  fail "S4 — a2t-nulmeting telt maar $aantal ID's; 'alles openstaand' verwacht"
fi

test_klaar
