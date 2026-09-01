#!/usr/bin/env bash
# lib/changes.sh — De gedeelde parser en predicaatlogica voor CHANGES.md.
#
# Sourcen, niet uitvoeren. Zowel adopt.sh als pending-changes.sh gebruikt dit;
# vóór deze bibliotheek stonden de predicaten letterlijk twee keer en het
# parserskelet ook, waardoor ze uit de pas konden lopen zonder dat iets klaagde.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

# De enige predicaatlogica. Uitgedrukt als case in plaats van eval van vrije
# tekst uit CHANGES.md: voorspelbaar, en een typefout levert "onbekend" op in
# plaats van een onbedoeld commando.
predicaat_waar() {
  local predicaat="$1" project_dir="$2"
  case "$predicaat" in
    altijd)
      return 0 ;;
    heeft-package-json)
      [ -f "$project_dir/package.json" ] ;;
    heeft-deploy-script)
      [ -f "$project_dir/package.json" ] &&
        grep -q '"deploy"[[:space:]]*:' "$project_dir/package.json" ;;
    *)
      return 1 ;;
  esac
}

# Loopt de entries in <bron> langs en roept <callback> aan met
# <id> <standaard> <predicaat>.
#
# Alleen entries mét een "Van toepassing als"-veld leiden tot een aanroep: dat
# veld is wat een entry actief maakt.
#
# Een `## `-kop zonder dat veld levert een waarschuwing op. Sinds de
# sectiescheidingen in CHANGES.md `###` zijn, betekent `## ` onvoorwaardelijk
# "entry", en is zo'n kop dus een vergeten predicaat in plaats van een kopje.
# Retirement gebeurt door te verhuizen naar CHANGES-ARCHIEF.md, niet door velden
# weg te laten. De waarschuwing gaat naar stderr: zichtbaar bij `check` en bij
# handmatig draaien, en onderdrukt in de SessionStart-hook, waar een project er
# toch niets aan kan doen.
#
# `standaard` is "ja" wanneer de entry geen `**Standaard:**`-veld draagt.
#
# **Contract voor de callback:** zijn exitstatus draagt geen betekenis voor deze
# lus, maar een niet-nul status wordt wel gemeld en telt mee in de eindstatus.
# Dat is bewust: zonder die afhandeling zou een callback die per ongeluk 1
# teruggeeft — bijvoorbeeld door een afsluitende `a && b` waarvan `a` onwaar is —
# een aanroeper met `set -e` stilzwijgend laten stoppen, halverwege de lus en
# zonder enige melding. adopt.sh draait met `set -e`, pending-changes.sh niet;
# die asymmetrie maakt zo'n fout makkelijk te maken en moeilijk te zien.
#
# De aanroeper beslist wat hij met `standaard` doet — dat is bewust niet hier
# geregeld. adopt.sh slaat `vraag` over (die entries worden nooit automatisch
# beantwoord); pending-changes.sh negeert het veld juist, want een onbeantwoorde
# vraag staat open ongeacht zijn startpunt. Een vlag in deze bibliotheek zou dat
# verschil verstoppen en op een ongelukje laten lijken; hier zichtbaar bij beide
# aanroepers is beter. Zie de comments daar, die naar elkaar verwijzen.
itereer_entries() {
  local bron="$1" callback="$2"
  local regel huidig_id="" standaard="ja" predicaat
  local fouten=0 gezien_predicaat=0

  # `|| [ -n "$regel" ]` vangt een bron zonder afsluitende newline op: read geeft
  # dan een niet-nul status terwijl de laatste regel wél gelezen is. Zonder dat
  # valt die regel weg — en sinds de waarschuwing hieronder zou een entry dan
  # stilzwijgend overgeslagen worden mét een misleidende melding erbij.
  while IFS= read -r regel || [ -n "$regel" ]; do
    case "$regel" in
      '## '*)
        if [ -n "$huidig_id" ] && [ "$gezien_predicaat" -eq 0 ]; then
          echo "waarschuwing: entry '$huidig_id' in $bron heeft geen 'Van toepassing als'-veld" >&2
        fi
        huidig_id="${regel#\#\# }"
        standaard="ja"
        gezien_predicaat=0 ;;
      *'**Standaard:**'*)
        standaard="${regel##*\*\* }"
        standaard="$(echo "$standaard" | tr -d '[:space:]')" ;;
      *'**Van toepassing als:**'*)
        predicaat="${regel##*\*\* }"
        predicaat="$(echo "$predicaat" | tr -d '[:space:]')"
        [ -n "$huidig_id" ] || continue
        gezien_predicaat=1
        if ! "$callback" "$huidig_id" "$standaard" "$predicaat"; then
          echo "waarschuwing: verwerking van entry '$huidig_id' gaf een fout" >&2
          fouten=$((fouten + 1))
        fi ;;
    esac
  done < "$bron"

  # Ook de laatste entry in het bestand telt mee.
  if [ -n "$huidig_id" ] && [ "$gezien_predicaat" -eq 0 ]; then
    echo "waarschuwing: entry '$huidig_id' in $bron heeft geen 'Van toepassing als'-veld" >&2
  fi

  [ "$fouten" -eq 0 ]
}

# Loopt béide bronnen langs: de entries in CHANGES.md en het NFR-register in
# nfr/. Sinds W5 staan de vijftien niet-functionele kenmerken niet meer als
# spec-*-entries in CHANGES.md, maar in een eigen register — deze functie houdt
# dat voor de aanroepers één ding.
#
# <workflow_dir> is de map met CHANGES.md en nfr/.
itereer_alle_entries() {
  local workflow_dir="$1" callback="$2"
  local fouten=0

  if [ -f "$workflow_dir/CHANGES.md" ]; then
    itereer_entries "$workflow_dir/CHANGES.md" "$callback" || fouten=$((fouten + 1))
  fi
  itereer_nfr "$workflow_dir/nfr" "$callback" || fouten=$((fouten + 1))

  [ "$fouten" -eq 0 ]
}
