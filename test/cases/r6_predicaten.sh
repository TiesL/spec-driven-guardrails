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
  for paar in "ci-conventie:$verwacht_ci" "ci-op-pr-en-main:$verwacht_ci" "deploy-guards:$verwacht_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$voor"; then feitelijk=ja; else feitelijk=nee; fi
    if [ "$feitelijk" != "$verwacht" ]; then
      fail "R6 — $naam: $id van toepassing=$feitelijk, tabel zegt $verwacht"
    fi
  done

  [ "$verwacht_ci" = "ja" ] && gezien_ci_waar=1
  [ "$verwacht_deploy" = "ja" ] && gezien_deploy_waar=1

  adopteer "$project"
  na="$SANDBOX/$naam-na.txt"
  samen="$SANDBOX/$naam-samen.txt"
  geseed="$SANDBOX/$naam-geseed.txt"
  openstaande_ids "$project" > "$na"
  geseede_ids "$project" > "$geseed"
  { cat "$geseed" "$na"; } | sort -u > "$samen"

  # And: wat adopt.sh seedt wordt rechtstreeks tegen de tabel gehouden. Dit is
  # de enige controle die ziet dat adopt.sh iets MIST. De vereniging hieronder
  # kan dat per constructie niet: wat adopt.sh niet seedt blijft gewoon
  # openstaan, waardoor de vereniging ongewijzigd blijft. Beide predicaat-
  # entries hebben `Standaard: ja`, dus van toepassing betekent hier geseed.
  for paar in "ci-conventie:$verwacht_ci" "ci-op-pr-en-main:$verwacht_ci" "deploy-guards:$verwacht_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$geseed"; then feitelijk=ja; else feitelijk=nee; fi
    if [ "$feitelijk" != "$verwacht" ]; then
      fail "R6 — $naam: adopt.sh seedde $id=$feitelijk, tabel zegt $verwacht"
    fi
  done

  # En het totaal: 20 entries gelden altijd, plus elke van toepassing zijnde
  # predicaat-entry. `heeft-package-json` draagt er sinds W24 twee -
  # `ci-conventie` (wat de workflow doet) en `ci-op-pr-en-main` (wanneer hij
  # draait). Vangt een seed-logica die er in bulk naast zit.
  verwacht_aantal=20
  [ "$verwacht_ci" = "ja" ] && verwacht_aantal=$((verwacht_aantal + 2))
  [ "$verwacht_deploy" = "ja" ] && verwacht_aantal=$((verwacht_aantal + 1))
  aantal_geseed="$(grep -c . "$geseed")"
  if [ "$aantal_geseed" -ne "$verwacht_aantal" ]; then
    fail "R6 — $naam: $aantal_geseed rijen geseed, $verwacht_aantal verwacht"
  fi

  # And: beide scripts komen tot hetzelfde antwoord. adopt.sh seedt de van
  # toepassing zijnde `Standaard: ja`-entries; wat daarna nog openstaat zijn de
  # `Standaard: vraag`-entries. Samen precies wat vóór de adoptie openstond.
  assert_ids_gelijk "R6 — $naam: seed-logica versus van_toepassing()" "$voor" "$samen"
done < "$tabel"

# And: voor elk predicaat is er minstens één geval waarin het waar is én de
# entry onbeantwoord. Zonder die eis blijft een te streng geworden predicaat
# onzichtbaar, want het verschil landt dan nergens in een openstaand-set.
[ "$gezien_ci_waar" -eq 1 ] || fail "R6 — geen enkel geval waarin heeft-package-json waar én onbeantwoord is"
[ "$gezien_deploy_waar" -eq 1 ] || fail "R6 — geen enkel geval waarin heeft-deploy-script waar én onbeantwoord is"

test_klaar
