#!/usr/bin/env bash
# lib/nfr.sh — The NFR register: parsing and generating the PRD block.
#
# Source, don't execute. The fifteen non-functional characteristics used to
# live in two places — as spec-* entries in CHANGES.md and as ### subsections
# in templates/PRD.md — which had to be kept in sync by hand. Now both are
# consumers of this register.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# Reads one field from a register file's frontmatter.
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

# Reads the content of a ## section from a register file, as a single line.
nfr_sectie() {
  local bestand="$1" kop="$2"
  awk -v k="## $kop" '
    { sub(/\r$/, "") }
    $0 == k { in_sec = 1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$bestand" | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//'
}

# The register files in order, one path per line.
#
# A missing or non-numeric `volgorde` field is loudly reported and the file
# goes to the back — never silently skipped. An NFR that unnoticeably falls
# out of the register disappears from *all* consumers at once: it's no
# longer asked, no longer seeded, and no longer in the template block — and
# because both sides miss it, the drift check sees nothing.
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

# Checks the register files for completeness. Prints every problem and
# returns 1 if something is wrong. `check` uses this: a broken register file
# should fail the build, not silently disappear.
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

# Walks the active register files, by `volgorde`, and calls <callback> with
# <id> <standaard> <predicaat>. Same signature as itereer_entries' callback,
# so a caller can treat both sources the same way.
#
# `status: geretireerd` skips the file. That's the retirement form for these
# fifteen: a field instead of moving the file.
itereer_nfr() {
  local nfr_map="$1" callback="$2"
  local bestand id standaard predicaat status fouten=0

  [ -d "$nfr_map" ] || return 0

  # Sorting on the volgorde field, not on filename: the order belongs to the
  # content (it determines the PRD block), not to what the file is called.
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

# The question text of one characteristic, as a single line.
# pending-changes.sh shows it for a pending change; since the spec-*
# entries were removed from CHANGES.md, this register is the only place it
# lives.
nfr_vraag() {
  local nfr_map="$1" id="$2"
  local bestand="$nfr_map/$id.md"
  [ -f "$bestand" ] || return 0
  nfr_sectie "$bestand" Vraag
}

# Prints the NFR block as it should appear in templates/PRD.md. The ID
# appears as an HTML comment in the output: pre-merge-review (W13) keys on
# that to link the review scope to the answered spec-* rows.
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
    # Wrapping at the same width as the rest of the template, so the block
    # reads as hand-written markdown and the diff on a change stays small.
    printf '<%s>\n' "$(nfr_sectie "$bestand" Invulhulp)" | fold -s -w 79 | sed 's/ *$//'

  done <<EOF
$lijst
EOF
}

# Turns an NFR block into one line per characteristic, with the ID up front.
# That way a diff between two blocks naturally names which characteristic
# differs, instead of only which line numbers.
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

# Compares the checked-in block in <sjabloon> with what the generator
# produces from <nfr_map>. Prints the differing characteristics and returns
# 1 if there's a difference.
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

  # First the order, in document order. nfr_records sorts by ID after all,
  # so a wrong order would drop out there against the comparison.
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
