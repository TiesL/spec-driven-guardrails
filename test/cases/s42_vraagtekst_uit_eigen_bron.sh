#!/usr/bin/env bash
# S42 — Elke gemelde wijziging toont de vraag uit zijn eigen bron.
# Dekt: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT

# Given: de openstaande wijzigingen van een project, uit beide bronnen.
project="$(vers_project doelproject)"
adopteer "$project"

uitvoer="$SANDBOX/uitvoer.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$uitvoer" 2>/dev/null

gezien=0
while IFS= read -r regel; do
  case "$regel" in
    '  - '*) ;;
    *) continue ;;
  esac
  id="${regel#  - }"; id="${id%% —*}"
  getoond="${regel#*— }"

  # De verwachte tekst komt uit de bron waar dit ID staat.
  verwacht="$(awk -v zoek="## $id" '
    $0 == zoek { in_entry = 1; next }
    in_entry && /\*\*Vraag:\*\*/ { sub(/.*\*\*Vraag:\*\* */, ""); print; exit }
    in_entry && /^## / { exit }
  ' "$TEST_REPO_ROOT/CHANGES.md")"
  bron="CHANGES.md"
  if [ -z "$verwacht" ]; then
    # Bewust niet via nfr_vraag(): dat is de functie die hier getest wordt.
    # Zou dit orakel diezelfde functie gebruiken, dan bewegen verwachting en
    # werkelijkheid samen mee en meet de test niets.
    verwacht="$(awk '
      /^## Vraag$/ { in_sec = 1; next }
      in_sec && /^## / { exit }
      in_sec { print }
    ' "$TEST_REPO_ROOT/nfr/$id.md" 2>/dev/null | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//')"
    bron="nfr/$id.md"
  fi

  if [ -z "$verwacht" ]; then
    fail "S42 — geen bron gevonden voor $id"
    continue
  fi
  if [ "$getoond" != "$verwacht" ]; then
    fail "S42 — $id toont niet de vraag uit $bron"
    echo "    getoond:  $getoond" >&2
    echo "    verwacht: $verwacht" >&2
  fi
  gezien=$((gezien + 1))
done < "$uitvoer"

[ "$gezien" -ge 7 ] || fail "S42 — maar $gezien regels gecontroleerd; de opzet deugt niet"

test_klaar
