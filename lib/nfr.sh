#!/usr/bin/env bash
# lib/nfr.sh — Het NFR-register: parsen en het PRD-blok genereren.
#
# Sourcen, niet uitvoeren. De vijftien niet-functionele kenmerken stonden eerder
# op twee plekken — als spec-*-entries in CHANGES.md en als ###-subsecties in
# templates/PRD.md — die met de hand synchroon gehouden moesten worden. Nu zijn
# beide consument van dit register.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

# Leest één veld uit de frontmatter van een registerbestand.
nfr_veld() {
  local bestand="$1" naam="$2"
  awk -v n="$naam" '
    { sub(/\r$/, "") }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"    { exit }
    in_fm && $0 ~ "^" n "[[:space:]]*:" {
      sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit
    }
  ' "$bestand"
}

# Leest de inhoud van een ##-sectie uit een registerbestand, als één regel.
nfr_sectie() {
  local bestand="$1" kop="$2"
  awk -v k="## $kop" '
    { sub(/\r$/, "") }
    $0 == k { in_sec = 1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$bestand" | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//'
}

# De registerbestanden op volgorde, één pad per regel.
#
# Een ontbrekend of niet-numeriek `volgorde`-veld wordt luid gemeld en het
# bestand gaat achteraan — nooit stilzwijgend overslaan. Een NFR die ongemerkt
# uit het register valt, verdwijnt namelijk uit álle consumenten tegelijk: hij
# wordt niet meer gevraagd, niet meer geseed en staat niet meer in het
# sjabloonblok — en omdat beide kanten hem missen, ziet de driftcontrole niets.
nfr_bestanden() {
  local nfr_map="$1" bestand vol
  [ -d "$nfr_map" ] || return 0
  for bestand in "$nfr_map"/*.md; do
    [ -e "$bestand" ] || continue
    vol="$(nfr_veld "$bestand" volgorde)"
    case "$vol" in
      ''|*[!0-9]*)
        echo "waarschuwing: $bestand heeft geen geldig 'volgorde'-veld — achteraan gezet" >&2
        vol=99999 ;;
    esac
    printf '%s\t%s\n' "$vol" "$bestand"
  done | sort -n | cut -f2-
}

# Controleert de registerbestanden op volledigheid. Print elk probleem en geeft
# 1 terug als er iets mis is. `check` gebruikt dit: een kapot registerbestand
# hoort de bouw te laten falen, niet stil te verdwijnen.
nfr_valideer() {
  local nfr_map="$1" bestand vol id kop pred status fouten=0

  [ -d "$nfr_map" ] || return 0

  for bestand in "$nfr_map"/*.md; do
    [ -e "$bestand" ] || continue
    id="$(nfr_veld "$bestand" id)"
    kop="$(nfr_veld "$bestand" kop)"
    vol="$(nfr_veld "$bestand" volgorde)"
    pred="$(nfr_veld "$bestand" van-toepassing-als)"
    status="$(nfr_veld "$bestand" status)"

    [ -n "$id" ]     || { echo "$bestand: veld 'id' ontbreekt"; fouten=$((fouten + 1)); }
    [ -n "$kop" ]    || { echo "$bestand: veld 'kop' ontbreekt"; fouten=$((fouten + 1)); }
    [ -n "$pred" ]   || { echo "$bestand: veld 'van-toepassing-als' ontbreekt"; fouten=$((fouten + 1)); }
    [ -n "$status" ] || { echo "$bestand: veld 'status' ontbreekt"; fouten=$((fouten + 1)); }
    case "$vol" in
      ''|*[!0-9]*) echo "$bestand: veld 'volgorde' ontbreekt of is niet numeriek"; fouten=$((fouten + 1)) ;;
    esac
    if [ -n "$id" ] && [ "$(basename "$bestand" .md)" != "$id" ]; then
      echo "$bestand: bestandsnaam en id ('$id') komen niet overeen"
      fouten=$((fouten + 1))
    fi
  done

  [ "$fouten" -eq 0 ]
}

# Loopt de actieve registerbestanden langs, op `volgorde`, en roept <callback>
# aan met <id> <standaard> <predicaat>. Dezelfde signatuur als de callback van
# itereer_entries, zodat een aanroeper beide bronnen gelijk kan behandelen.
#
# `status: geretireerd` slaat het bestand over. Dat is de retirementvorm voor
# deze vijftien: een veld in plaats van een bestandsverhuizing.
itereer_nfr() {
  local nfr_map="$1" callback="$2"
  local bestand id standaard predicaat status fouten=0

  [ -d "$nfr_map" ] || return 0

  # Sorteren op het volgorde-veld, niet op bestandsnaam: de volgorde hoort bij
  # de inhoud (hij bepaalt het PRD-blok) en niet bij hoe het bestand heet.
  local lijst
  lijst="$(nfr_bestanden "$nfr_map")"

  while IFS= read -r bestand; do
    [ -n "$bestand" ] || continue
    status="$(nfr_veld "$bestand" status)"
    [ "$status" = "geretireerd" ] && continue

    id="$(nfr_veld "$bestand" id)"
    standaard="$(nfr_veld "$bestand" standaard)"
    predicaat="$(nfr_veld "$bestand" van-toepassing-als)"

    if [ -z "$id" ] || [ -z "$predicaat" ]; then
      echo "waarschuwing: $bestand mist een id of van-toepassing-als" >&2
      continue
    fi

    if ! "$callback" "$id" "$standaard" "$predicaat"; then
      echo "waarschuwing: verwerking van NFR '$id' gaf een fout" >&2
      fouten=$((fouten + 1))
    fi
  done <<EOF
$lijst
EOF

  [ "$fouten" -eq 0 ]
}

# De vraagtekst van één kenmerk, als één regel. pending-changes.sh toont die bij
# een openstaande wijziging; sinds de spec-*-entries uit CHANGES.md zijn gehaald
# is dit register de enige plek waar hij staat.
nfr_vraag() {
  local nfr_map="$1" id="$2"
  local bestand="$nfr_map/$id.md"
  [ -f "$bestand" ] || return 0
  nfr_sectie "$bestand" Vraag
}

# Print het NFR-blok zoals het in templates/PRD.md hoort te staan. Het ID staat
# als HTML-commentaar in de uitvoer: daar keyt pre-merge-review (W13) op om de
# reviewscope aan de beantwoorde spec-*-rijen te koppelen.
nfr_blok() {
  local nfr_map="$1"
  local bestand kop id status lijst

  lijst="$(nfr_bestanden "$nfr_map")"

  while IFS= read -r bestand; do
    [ -n "$bestand" ] || continue
    status="$(nfr_veld "$bestand" status)"
    [ "$status" = "geretireerd" ] && continue
    kop="$(nfr_veld "$bestand" kop)"
    id="$(nfr_veld "$bestand" id)"
    echo
    echo "### $kop"
    echo "<!-- nfr: $id -->"
    # Wikkelen op dezelfde breedte als de rest van het sjabloon, zodat het blok
    # als handgeschreven markdown leest en de diff bij een wijziging klein is.
    printf '<%s>\n' "$(nfr_sectie "$bestand" Invulhulp)" | fold -s -w 79 | sed 's/ *$//'

  done <<EOF
$lijst
EOF
}

# Zet een NFR-blok om naar één regel per kenmerk, met het ID vooraan. Zo noemt
# een diff tussen twee blokken vanzelf welk kenmerk verschilt, in plaats van
# alleen welke regelnummers.
nfr_records() {
  awk '
    BEGIN { RS = ""; FS = "\n" }
    {
      id = "onbekend"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /<!-- nfr: /) {
          id = $i
          sub(/.*<!-- nfr: */, "", id)
          sub(/ *-->.*/, "", id)
        }
      }
      regel = $0
      gsub(/\n/, " ", regel)
      print id "\t" regel
    }
  ' | sort
}

# Vergelijkt het ingecheckte blok in <sjabloon> met wat de generator uit
# <nfr_map> produceert. Print de afwijkende kenmerken en geeft 1 terug als er
# verschil is.
nfr_drift() {
  local nfr_map="$1" sjabloon="$2"
  local ingecheckt gegenereerd verschil status=0

  ingecheckt="$(mktemp)"
  gegenereerd="$(mktemp)"

  local blok_ingecheckt blok_gegenereerd
  blok_ingecheckt="$(mktemp)"
  blok_gegenereerd="$(mktemp)"

  awk '
    /<!-- nfr-blok:begin/ { in_blok = 1; next }
    /<!-- nfr-blok:eind/  { in_blok = 0 }
    in_blok { print }
  ' "$sjabloon" > "$blok_ingecheckt"
  nfr_blok "$nfr_map" > "$blok_gegenereerd"

  # Eerst de vololgorde, in documentvolgorde. nfr_records sorteert namelijk op
  # ID, waardoor een verkeerde volgorde daar wegvalt tegen de vergelijking.
  local volgorde_in volgorde_gen
  volgorde_in="$(grep -oE '<!-- nfr: [a-z-]+' "$blok_ingecheckt" | sed 's/.*nfr: //' | tr '\n' ' ')"
  volgorde_gen="$(grep -oE '<!-- nfr: [a-z-]+' "$blok_gegenereerd" | sed 's/.*nfr: //' | tr '\n' ' ')"
  if [ "$volgorde_in" != "$volgorde_gen" ]; then
    status=1
    echo "volgorde van het blok wijkt af"
  fi

  nfr_records < "$blok_ingecheckt" > "$ingecheckt"
  nfr_records < "$blok_gegenereerd" > "$gegenereerd"
  rm -f "$blok_ingecheckt" "$blok_gegenereerd"

  if ! diff -q "$ingecheckt" "$gegenereerd" >/dev/null 2>&1; then
    status=1
    verschil="$(diff "$ingecheckt" "$gegenereerd" | grep -E '^[<>]' | awk '{print $2}' | sort -u)"
    printf '%s\n' "$verschil"
  fi

  rm -f "$ingecheckt" "$gegenereerd"
  return "$status"
}
