#!/usr/bin/env bash
# templates/check-main-via-pr.sh — CI detecteert commits op main die niet uit
# een PR komen (W27, F17). Detectie, geen preventie: het commando is dan al
# uitgevoerd. De lokale hooks (W10, W26) voorkomen; dit vangt op wat er op een
# andere machine of met een ander gereedschap doorheen glipt — het enige
# mechanisme dat werkt zonder GitHub Pro/publieke repo (serverzijdige branch
# protection is dan dicht).
#
# Aanroepen vanuit CI, op het push-naar-main-event, met de SHA als argument:
#
#   ./check-main-via-pr.sh "$GITHUB_SHA"
#
# Beoordeelt alleen déze push, geen audit over de geschiedenis — zelfde reden
# als bij check-pr-issue-link.sh (W19b): een retrofit die op dag één rood
# staat leert je de melding te negeren.
#
# Geen faal-open: kan de herkomst niet worden vastgesteld (geen API-antwoord,
# ontbrekende rechten), dan faalt de controle met de reden erbij. Dat is
# bewust het omgekeerde van de lokale git-hooks (S58): een lokale hook die
# faalt houdt werk tegen dat allang legitiem kan zijn, een CI-controle die
# stil groen wordt meldt "niets aan de hand" terwijl hij niets weet.
#
# Vereist gh + een token met leestoegang; op GitHub Actions is GITHUB_TOKEN
# gratis beschikbaar.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

set -uo pipefail

sha="${1:?gebruik: check-main-via-pr.sh <sha>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "check-main-via-pr: gh ontbreekt — kan de herkomst van $sha niet vaststellen." >&2
  exit 1
fi

aantal="$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" --jq 'length' 2>/dev/null)"

# Alles behalve een schoon niet-negatief getal is "kon niet vaststellen" — ook
# lege uitvoer. Zonder deze check faalt de vergelijking hieronder stil (bash
# meldt een geheeltallige-expressie-fout, maar set -e staat uit) en loopt het
# script door naar exit 0 — precies het faal-openpad dat dit script uitsluit.
case "$aantal" in
  ''|*[!0-9]*)
    echo "check-main-via-pr: kon de herkomst van commit $sha niet vaststellen." >&2
    exit 1 ;;
esac

if [ "$aantal" -eq 0 ]; then
  echo "check-main-via-pr: commit $sha op main komt niet uit een pull request." >&2
  exit 1
fi

exit 0
