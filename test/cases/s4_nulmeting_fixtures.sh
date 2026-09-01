#!/usr/bin/env bash
# S4 — Nulmeting-fixture legt `a2t-emails` vast zoals gevonden, en elke fixture
# reproduceert zijn eigen gouden set.
# Dekt: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"

# Elke fixture moet zijn eigen gouden set reproduceren. Wijkt dat af, dan is óf
# de nulmeting fout vastgelegd, óf het gedrag veranderd - allebei precies wat
# deze fixtures moeten opvangen.
for project in a2t-emails tennis-admin tennis-registration tennis-invoicing; do
  fixture="$nulmeting/$project"

  if [ ! -d "$fixture" ]; then
    fail "S4 — fixture ontbreekt: $project"
    continue
  fi

  gouden="$fixture/verwacht-openstaand.txt"
  if [ ! -f "$gouden" ]; then
    fail "S4 — gouden set ontbreekt: $project/verwacht-openstaand.txt"
    continue
  fi

  huidig="$(mktemp)"
  "$TEST_REPO_ROOT/pending-changes.sh" "$fixture" 2>/dev/null \
    | grep '^  - ' | sed 's/^  - //; s/ —.*//' | sort > "$huidig"

  if ! diff -u "$gouden" "$huidig" >/dev/null 2>&1; then
    fail "S4 — $project wijkt af van de vastgelegde nulmeting:"
    diff -u "$gouden" "$huidig" >&2
  fi
  rm -f "$huidig"
done

# a2t-emails is het bijzondere geval: geen WORKFLOW-ADOPTIE.md, dus alles staat
# open. Vastleggen zoals gevonden - niet eerst repareren, anders legt de fixture
# de reparatie vast in plaats van de toestand.
a2t="$nulmeting/a2t-emails"

if [ -e "$a2t/WORKFLOW-ADOPTIE.md" ]; then
  fail "S4 — de a2t-emails-fixture heeft een WORKFLOW-ADOPTIE.md; die hoort er niet te zijn"
fi

# Niet-circulaire controle dat er niets vooraf beantwoord is: ci-conventie is in
# tennis-admin wél beantwoord. Staat hij hier open, dan is de fixture ongerepareerd.
if [ -f "$a2t/verwacht-openstaand.txt" ]; then
  if ! grep -qx 'ci-conventie' "$a2t/verwacht-openstaand.txt"; then
    fail "S4 — ci-conventie ontbreekt in de a2t-nulmeting; lijkt vooraf beantwoord"
  fi
  aantal="$(grep -c . "$a2t/verwacht-openstaand.txt")"
  if [ "$aantal" -lt 20 ]; then
    fail "S4 — a2t-nulmeting telt maar $aantal ID's; 'alles openstaand' verwacht"
  fi
fi

test_klaar
