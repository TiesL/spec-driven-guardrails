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
# vorm van nfr/, precies het gat dat W28 dicht.
for project in a2t-emails tennis-admin tennis-registration tennis-invoicing; do
  gouden="$nulmeting/$project/verwacht-openstaand.txt"
  [ -f "$gouden" ] || continue
  while IFS= read -r id; do
    case "$id" in
      spec-*)
        if [ ! -f "$snapshot/$id.md" ]; then
          fail "S66 — $id (gouden set van $project) heeft geen ingevroren bron in nfr.momentopname"
        fi ;;
    esac
  done < "$gouden"
done

test_klaar
