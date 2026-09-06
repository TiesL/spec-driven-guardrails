#!/usr/bin/env bash
# S66 — De bron van de vraagset is volledig ingevroren, ook het nfr-deel.
# Dekt: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"
snapshot="$nulmeting/nfr.momentopname"

if [ ! -d "$snapshot" ]; then
  fail "S66 — test/fixtures/nulmeting/nfr.momentopname ontbreekt: het nfr-deel van de vraagset is niet ingevroren"
  test_klaar
fi

aantal="$(find "$snapshot" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
if [ "$aantal" -lt 1 ]; then
  fail "S66 — nfr.momentopname bevat geen enkel bestand"
fi

# AC5: het mag een afgeleide/gekopieerde momentopname zijn, mits die zelf
# geldig blijft — een corrupte freeze zou het vangnet stil laten leeglopen.
# shellcheck source=../../lib/nfr.sh
. "$TEST_REPO_ROOT/lib/nfr.sh"
if ! problemen="$(nfr_valideer "$snapshot")"; then
  fail "S66 — nfr.momentopname is zelf niet geldig:"
  printf '%s\n' "$problemen" >&2
fi

# Elk spec-*-ID uit elke gouden set moet herleidbaar zijn tot een ingevroren
# nfr-bestand — anders hangt dat ID alleen af van de actuele, niet-ingevroren
# vorm van nfr/, precies het gat dat W28 dicht. Een ontbrekende gouden set is
# hier, net als in R9, een fout en geen reden om die fixture stilzwijgend over
# te slaan.
for project in $NULMETING_PROJECTEN; do
  gouden="$nulmeting/$project/verwacht-openstaand.txt"
  if [ ! -f "$gouden" ]; then
    fail "S66 — gouden set ontbreekt: $project"
    continue
  fi
  while IFS= read -r id; do
    case "$id" in
      spec-*)
        if [ ! -f "$snapshot/$id.md" ]; then
          fail "S66 — $id (gouden set van $project) heeft geen ingevroren bron in nfr.momentopname"
        fi ;;
    esac
  done < "$gouden"
done

# De rookmelder: nfr.momentopname/ moet vandaag exact gelijk zijn aan nfr/.
# Dat hoort op een dag te gaan afgaan — namelijk zodra nfr/ legitiem wijzigt
# zonder dat de freeze meeverst — en dat is precies het moment waarop
# LEESMIJ.md's ververs-procedure van toepassing wordt. Zonder deze controle
# zou een verwijderd, geretireerd of inhoudelijk gewijzigd registerbestand de
# momentopname stil laten verouderen: S66 hierboven ziet alleen ID's die in
# een gouden set voorkomen, niet elk registerbestand op zich.
if ! verschil="$(diff -r "$TEST_REPO_ROOT/nfr" "$snapshot" 2>&1)"; then
  fail "S66 — nfr.momentopname loopt uit de pas met nfr/ (zie LEESMIJ.md om te verversen):"
  printf '%s\n' "$verschil" >&2
fi

test_klaar
