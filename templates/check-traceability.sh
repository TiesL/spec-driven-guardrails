#!/usr/bin/env bash
# Schakel 1 van de traceabilityketen: elke functionaliteit heeft een scenario,
# en elke dekkingsverwijzing lost op.
#
# Aanroepen vanuit het `check` van het project:
#
#   ./check-traceability.sh .
#
# Bewust offline en zonder `gh`: dit is de enige schakel die geen netwerk nodig
# heeft, en een controle die netwerk vraagt hoort niet in een lokale `check`.
# De schakels scenario -> issue -> PR zitten in `pre-merge-review` en in CI.
#
# Geen `eval`. Dit script leest tekst die niet volledig onder eigen beheer staat;
# een ID dat per ongeluk een commando is, mag nooit iets uitvoeren.

set -uo pipefail

project="${1:-.}"
prd="$project/PRD.md"
scenarios="$project/TEST-SCENARIOS.md"

fouten=0
melding() { echo "traceability: $1" >&2; fouten=$((fouten + 1)); }
waarschuwing() { echo "traceability: waarschuwing — $1" >&2; }

for bestand in "$prd" "$scenarios"; do
  if [ ! -f "$bestand" ]; then
    waarschuwing "${bestand#"$project"/} ontbreekt — niets te controleren"
    exit 0
  fi
done

# De ID's uit de koppen van een bestand, één per regel.
#
# Alleen koppen tellen. Een ID in lopende tekst is geen definitie, en een
# schrijfwijze als "F13a" in een zin zou anders een niet-bestaand item in het
# leven roepen. Het prefix ligt niet vast: `F`/`S` is gebruikelijk, maar
# `R`/`A`/`B`/`P` en `OP` komen in bestaande projecten voor, en een hardcoded
# lijst maakt dit script daar op dag één onbruikbaar.
ids_uit_koppen() {
  grep -oE '^#+[[:space:]]+[A-Z]{1,2}[0-9]+[a-z]?([[:space:]]|$)' "$1" \
    | sed 's/^#*[[:space:]]*//; s/[[:space:]]*$//'
}

# De Dekt:-tokens uit een bestand, één per regel.
#
# Alleen het veld telt, aan regelbegin. Dat voorkomt vals-positieven per
# constructie: een zin die toevallig "S1" bevat is geen verwijzing.
#
# Tokens tussen punthaken worden overgeslagen. Een vers gescaffold project draagt
# `**Dekt:** <F1>` uit het sjabloon, en een controle die daarop meteen faalt,
# staat morgen uit.
dekt_tokens() {
  grep '^\*\*Dekt:\*\*' "$1" \
    | sed 's/^\*\*Dekt:\*\*[[:space:]]*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -E '^[A-Z]{1,2}[0-9]+[a-z]?$'
}

prd_ids="$(ids_uit_koppen "$prd")"
scenario_ids="$(ids_uit_koppen "$scenarios")"

# Dubbele ID's binnen één bestand. Dat is een echte fout, geen stijlkwestie: een
# verwijzing naar zo'n ID is niet meer eenduidig op te lossen.
for paar in "PRD.md:$prd_ids" "TEST-SCENARIOS.md:$scenario_ids"; do
  naam="${paar%%:*}"
  dubbel="$(printf '%s\n' "${paar#*:}" | grep -v '^$' | sort | uniq -d)"
  if [ -n "$dubbel" ]; then
    for id in $dubbel; do
      melding "$naam bevat $id meer dan één keer — een verwijzing ernaar is niet eenduidig"
    done
  fi
done

# Een PRD zonder ID's is geen fout maar een waarschuwing. Eén van de vier
# bestaande projecten is precies dit geval; hard falen zou het script daar
# meteen uitschakelen en dan controleert het nergens meer iets.
if [ -z "$prd_ids" ]; then
  waarschuwing "PRD.md heeft geen ID-koppen — schakel 1 is hier niet te controleren"
  [ "$fouten" -eq 0 ] && exit 0
  exit 1
fi

# Elk Dekt:-token lost op in de ID's van het ándere bestand.
controleer_verwijzingen() {
  local bestand="$1" naam="$2" doelen="$3" doelnaam="$4" token
  for token in $(dekt_tokens "$bestand"); do
    printf '%s\n' "$doelen" | grep -qx "$token" \
      || melding "$naam verwijst naar $token, maar dat ID bestaat niet in $doelnaam"
  done
}
controleer_verwijzingen "$scenarios" "TEST-SCENARIOS.md" "$prd_ids" "PRD.md"
controleer_verwijzingen "$prd" "PRD.md" "$scenario_ids" "TEST-SCENARIOS.md"

# Schakel 1 zelf: elke functionaliteit is door minstens één scenario gedekt.
#
# Draagt geen enkel scenario een Dekt:-veld, dan gebruikt dit project de
# conventie nog niet. Dan is elke functionaliteit per definitie ongedekt, en zou
# dit script bij invoering in één klap over álle items klagen. Dat is de
# retrofit die het ontwerp juist vermijdt: de conventie geldt vanaf het
# eerstvolgende werk. Vandaar een waarschuwing, en handhaving zodra de eerste
# verwijzing er staat.
gedekt="$(dekt_tokens "$scenarios" | sort -u)"
if [ -z "$gedekt" ]; then
  waarschuwing "TEST-SCENARIOS.md draagt nog geen Dekt:-velden — schakel 1 wordt pas gehandhaafd zodra de eerste verwijzing er staat"
  [ "$fouten" -eq 0 ] && exit 0
  exit 1
fi

for id in $prd_ids; do
  printf '%s\n' "$gedekt" | grep -qx "$id" \
    || melding "$id heeft geen enkel scenario dat het dekt"
done

[ "$fouten" -eq 0 ] || exit 1
echo "traceability: in orde"
