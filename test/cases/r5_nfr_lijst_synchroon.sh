#!/usr/bin/env bash
# R5 — NFR-lijst blijft 1-op-1 synchroon.
# Dekt: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

nfr_map="$TEST_REPO_ROOT/nfr"
sjabloon="$TEST_REPO_ROOT/templates/PRD.md"

if [ ! -d "$nfr_map" ]; then
  fail "R5 — nfr/ ontbreekt"
  test_klaar
fi

# Given: de NFR-ID's uit het register en de ###-subsecties in het sjabloon.
uit_register="$SANDBOX/register.txt"
uit_sjabloon="$SANDBOX/sjabloon.txt"

# Het register levert het paar id/kop uit hetzelfde bestand — geen normalisatie
# van "spec-compliance" naar "Compliance en auditeerbaarheid" nodig.
for bestand in "$nfr_map"/*.md; do
  [ -e "$bestand" ] || continue
  id="$(awk -F': *' '/^id:/{print $2; exit}' "$bestand")"
  kop="$(awk -F': *' '/^kop:/{print $2; exit}' "$bestand")"
  status="$(awk -F': *' '/^status:/{print $2; exit}' "$bestand")"
  [ "$status" = "geretireerd" ] && continue
  if [ -z "$id" ] || [ -z "$kop" ]; then
    fail "R5 — $(basename "$bestand") mist een id of kop"
    continue
  fi
  printf '%s\t%s\n' "$id" "$kop" >> "$uit_register"
done
sort -o "$uit_register" "$uit_register" 2>/dev/null || : > "$uit_register"

# Het sjabloon levert de koppen uit het gegenereerde blok, met het ID uit het
# HTML-commentaar dat de generator erbij zet.
awk '
  /<!-- nfr-blok:begin/ { in_blok = 1; next }
  /<!-- nfr-blok:eind/  { in_blok = 0 }
  in_blok && /^### /     { kop = substr($0, 5) }
  in_blok && /<!-- nfr:/ { id = $0; sub(/.*<!-- nfr: */, "", id); sub(/ *-->.*/, "", id); print id "\t" kop }
' "$sjabloon" | sort > "$uit_sjabloon"

# Then: exacte 1-op-1-overeenkomst, geen ontbrekende of overtollige kant.
aantal="$(grep -c . "$uit_register" 2>/dev/null || echo 0)"
[ "$aantal" -eq 15 ] || fail "R5 — $aantal actieve NFR's in het register, 15 verwacht"

if ! diff -u "$uit_register" "$uit_sjabloon" >/dev/null 2>&1; then
  fail "R5 — register en sjabloon lopen uit de pas:"
  diff -u "$uit_register" "$uit_sjabloon" >&2
fi

# And: geen spec-*-entries meer in CHANGES.md — het register is de enige bron.
if grep -q '^## spec-' "$TEST_REPO_ROOT/CHANGES.md"; then
  fail "R5 — CHANGES.md bevat nog spec-*-entries"
  grep -n '^## spec-' "$TEST_REPO_ROOT/CHANGES.md" >&2
fi

test_klaar
