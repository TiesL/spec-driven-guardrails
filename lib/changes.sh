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
# veld is wat een entry actief maakt. Een geretireerde entry laat het weg en
# wordt daarmee nergens meer geseed of gevraagd.
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
  local fouten=0

  while IFS= read -r regel; do
    case "$regel" in
      '## '*)
        huidig_id="${regel#\#\# }"
        standaard="ja" ;;
      *'**Standaard:**'*)
        standaard="${regel##*\*\* }"
        standaard="$(echo "$standaard" | tr -d '[:space:]')" ;;
      *'**Van toepassing als:**'*)
        predicaat="${regel##*\*\* }"
        predicaat="$(echo "$predicaat" | tr -d '[:space:]')"
        [ -n "$huidig_id" ] || continue
        if ! "$callback" "$huidig_id" "$standaard" "$predicaat"; then
          echo "waarschuwing: verwerking van entry '$huidig_id' gaf een fout" >&2
          fouten=$((fouten + 1))
        fi ;;
    esac
  done < "$bron"

  [ "$fouten" -eq 0 ]
}
