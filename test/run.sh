#!/usr/bin/env bash
# test/run.sh — Draait alle testgevallen in test/cases/.
#
# Elk testgeval is een zelfstandig script dat test/lib.sh sourcet en met een
# nulstatus eindigt als het slaagt. Ze draaien elk in een eigen proces, zodat
# een test die zijn HOME omzet dat nooit voor een volgende test doet.
#
# Gebruik: ./test/run.sh [naamfragment]

set -uo pipefail

hier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="${1:-}"

# Verdediging in de diepte. sandbox_guard is opt-in per testgeval; een test die
# sandbox_create vergeet zou zonder dit in de echte home schrijven. Door HOME
# hier al naar een schildwachtmap te wijzen, kan zo'n vergeten aanroep hooguit
# daar landen - en dat is achteraf zichtbaar.
# De echte home eerst vastleggen: hem in dezelfde commando-prefix uitlezen
# waarin HOME wordt overschreven, leest verwarrend (SC2097/SC2098).
echte_home="$HOME"
schildwacht="$(mktemp -d)"
trap 'rm -rf "$schildwacht"' EXIT

geslaagd=0
gefaald=0
mislukt=""

for geval in "$hier"/cases/*.sh; do
  [ -e "$geval" ] || continue
  naam="$(basename "$geval" .sh)"
  if [ -n "$filter" ]; then
    case "$naam" in
      *"$filter"*) ;;
      *) continue ;;
    esac
  fi

  echo "  $naam"
  rm -rf "${schildwacht:?}"/*
  if TEST_REAL_HOME="$echte_home" HOME="$schildwacht" bash "$geval"; then
    geslaagd=$((geslaagd + 1))
  else
    gefaald=$((gefaald + 1))
    mislukt="$mislukt $naam"
  fi
  if [ -n "$(ls -A "$schildwacht" 2>/dev/null)" ]; then
    echo "    waarschuwing: $naam schreef in HOME zonder sandbox_create" >&2
  fi
done

echo
if [ "$gefaald" -gt 0 ]; then
  echo "Tests: $geslaagd geslaagd, $gefaald gefaald —$mislukt" >&2
  exit 1
fi

if [ "$geslaagd" -eq 0 ]; then
  echo "Tests: geen enkel testgeval gedraaid — dat is geen groen." >&2
  exit 1
fi

echo "Tests: $geslaagd geslaagd."
