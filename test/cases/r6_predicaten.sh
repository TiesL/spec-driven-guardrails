#!/usr/bin/env bash
# R6 — Predicaatgedrag identiek én aantoonbaar juist.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

tabel="$TEST_REPO_ROOT/test/fixtures/predicaten/waarheidstabel.txt"
[ -f "$tabel" ] || { fail "R6 — waarheidstabel ontbreekt"; test_klaar; }

gezien_ci_waar=0
gezien_deploy_waar=0

while IFS='|' read -r naam heeft_pkg inhoud verwacht_ci verwacht_deploy; do
  case "$naam" in ''|'#'*) continue ;; esac

  # Given: een vers project volgens deze combinatie. Geen WORKFLOW-ADOPTIE.md,
  # dus elke van toepassing zijnde entry staat ook open - daardoor is een te
  # streng geworden predicaat hier wél zichtbaar.
  project="$(vers_project "$naam")"
  [ "$heeft_pkg" = "ja" ] && printf '%s\n' "$inhoud" > "$project/package.json"

  voor="$SANDBOX/$naam-voor.txt"
  openstaande_ids "$project" > "$voor"

  # Then: de uitkomst per combinatie is precies wat de tabel vastlegt.
  for paar in "ci-conventie:$verwacht_ci" "deploy-guards:$verwacht_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$voor"; then feitelijk=ja; else feitelijk=nee; fi
    if [ "$feitelijk" != "$verwacht" ]; then
      fail "R6 — $naam: $id van toepassing=$feitelijk, tabel zegt $verwacht"
    fi
  done

  [ "$verwacht_ci" = "ja" ] && gezien_ci_waar=1
  [ "$verwacht_deploy" = "ja" ] && gezien_deploy_waar=1

  # And: beide scripts komen tot exact hetzelfde antwoord. adopt.sh seedt de van
  # toepassing zijnde `Standaard: ja`-entries; wat daarna nog openstaat zijn de
  # van toepassing zijnde `Standaard: vraag`-entries. Samen moeten die precies de
  # set zijn die pending-changes.sh vóór de adoptie meldde.
  adopteer "$project"
  na="$SANDBOX/$naam-na.txt"
  samen="$SANDBOX/$naam-samen.txt"
  openstaande_ids "$project" > "$na"
  { geseede_ids "$project"; cat "$na"; } | sort -u > "$samen"

  assert_ids_gelijk "R6 — $naam: seed-logica versus van_toepassing()" "$voor" "$samen"
done < "$tabel"

# And: voor elk predicaat is er minstens één geval waarin het waar is én de
# entry onbeantwoord. Zonder die eis blijft een te streng geworden predicaat
# onzichtbaar, want het verschil landt dan nergens in een openstaand-set.
[ "$gezien_ci_waar" -eq 1 ] || fail "R6 — geen enkel geval waarin heeft-package-json waar én onbeantwoord is"
[ "$gezien_deploy_waar" -eq 1 ] || fail "R6 — geen enkel geval waarin heeft-deploy-script waar én onbeantwoord is"

test_klaar
