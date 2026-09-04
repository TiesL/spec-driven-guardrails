#!/usr/bin/env bash
# S7 — Het signaal telt rijen die nog op onderbouwing wachten.
# Dekt: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een vers geadopteerd project met 17 geseede rijen die "vereist
# onderbouwing" dragen.
project="$(vers_project doelproject)"
adopteer "$project"

rijen="$(grep -c 'vereist onderbouwing' "$project/WORKFLOW-ADOPTIE.md")"
[ "$rijen" -eq 18 ] || fail "S7 — $rijen rijen met 'vereist onderbouwing', 18 verwacht"

# When: pending-changes.sh draait.
uitvoer="$SANDBOX/uitvoer.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$uitvoer" 2>/dev/null

# Then: er verschijnt een melding met het aantal.
grep -q '18 rij(en)' "$uitvoer" || {
  fail "S7 — geen melding met het aantal wachtende onderbouwingen"
  cat "$uitvoer" >&2
}
grep -qi 'onderbouwing' "$uitvoer" || fail "S7 — de melding noemt 'onderbouwing' niet"

# En het aantal beweegt mee: één rij onderbouwen maakt er zeventien van.
# Eén rij onderbouwen. Niet met `sed '0,/re/'`: dat adresbereik is een
# GNU-uitbreiding die BSD-sed op macOS niet kent, en de vervanging grijpt dan
# stilzwijgend niet.
awk '
  !gedaan && sub(/vereist onderbouwing tijdens PRD\/architectuur/, "onderbouwd: dit project verwerkt persoonsgegevens") { gedaan = 1 }
  { print }
' "$project/WORKFLOW-ADOPTIE.md" > "$SANDBOX/tabel.tmp"
mv "$SANDBOX/tabel.tmp" "$project/WORKFLOW-ADOPTIE.md"

na="$SANDBOX/na.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$na" 2>/dev/null
grep -q '17 rij(en)' "$na" || {
  fail "S7 — het aantal beweegt niet mee na het onderbouwen van één rij"
  grep -i 'rij(en)' "$na" >&2
}

# Zijn alle rijen onderbouwd, dan verdwijnt de melding — anders wordt hij ruis.
sed -i.bak 's/bij adoptie — vereist onderbouwing tijdens PRD\/architectuur/onderbouwd/g' \
  "$project/WORKFLOW-ADOPTIE.md"
rm -f "$project/WORKFLOW-ADOPTIE.md.bak"

leeg="$SANDBOX/leeg.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$leeg" 2>/dev/null
if grep -qi 'wachten nog op onderbouwing' "$leeg"; then
  fail "S7 — de melding blijft staan terwijl alles onderbouwd is"
fi

# En de telling kijkt alleen naar tabelrijen. Een losse notitie buiten de tabel
# die toevallig dezelfde woorden bevat, is geen wachtende onderbouwing —
# beantwoord() ankert om dezelfde reden op de ID-kolom.
printf '\nLosse notitie: dit vereist onderbouwing bij gelegenheid.\n' \
  >> "$project/WORKFLOW-ADOPTIE.md"

met_notitie="$SANDBOX/met-notitie.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$met_notitie" 2>/dev/null
if grep -qi 'wachten nog op onderbouwing' "$met_notitie"; then
  fail "S7 — een notitie buiten de tabel telt mee als wachtende onderbouwing"
  grep -i 'rij(en)' "$met_notitie" >&2
fi

test_klaar
