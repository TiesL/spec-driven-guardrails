#!/usr/bin/env bash
# S84 — install.sh installeert een gepinde versie, niet de actuele main.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een sandboxkopie van dit repo, met een eigen git-geschiedenis en een
# tag op de "oude" staat, gevolgd door een commit die WORKFLOW.md wijzigt —
# zodat een geslaagde pin aantoonbaar de oude inhoud teruggeeft, niet de
# nieuwe.
repo="$(sandbox_copy_repo)"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  add -A
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q -m "oude versie"
git -C "$repo" tag oude-versie

echo "NIEUWE INHOUD DIE NIET GEPIND MAG WORDEN" >> "$repo/WORKFLOW.md"
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  add -A
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q -m "nieuwe versie"

oude_commit="$(git -C "$repo" rev-parse oude-versie)"

# When: install.sh draait met een expliciete, bestaande tag.
uitvoer="$(cd "$repo" && ./install.sh oude-versie 2>&1)"
status=$?

# Then: HEAD staat op de gepinde commit, niet op de nieuwe.
[ "$status" -eq 0 ] || fail "S84 — install.sh met een geldige tag gaf exitstatus $status: $uitvoer"
huidige_commit="$(git -C "$repo" rev-parse HEAD)"
[ "$huidige_commit" = "$oude_commit" ] \
  || fail "S84 — na install.sh oude-versie staat HEAD niet op de gepinde commit"
if grep -q "NIEUWE INHOUD" "$repo/WORKFLOW.md"; then
  fail "S84 — WORKFLOW.md bevat na de pin nog de nieuwere inhoud"
fi

# And: een vieze werkmap wordt geweigerd, zonder iets uit te checken.
echo "lokale, niet-gecommitte wijziging" >> "$repo/README.md"
vies_uitvoer="$(cd "$repo" && ./install.sh oude-versie 2>&1)"
vies_status=$?
[ "$vies_status" -ne 0 ] || fail "S84 — install.sh met een vieze werkmap werd niet geweigerd"
assert_contains "S84 — de weigering noemt de niet-gecommitte wijzigingen" "wijziging" "$vies_uitvoer"
git -C "$repo" checkout -q -- README.md

# And: een onbekende tag faalt met een duidelijke melding.
onbekend_uitvoer="$(cd "$repo" && ./install.sh deze-tag-bestaat-niet 2>&1)"
onbekend_status=$?
[ "$onbekend_status" -ne 0 ] || fail "S84 — een onbekende tag werd niet geweigerd"
assert_contains "S84 — de melding noemt dat de tag niet bestaat" "bestaat niet" "$onbekend_uitvoer"

# And: zonder argument wordt de laatste tag gebruikt, expliciet gemeld.
zonder_arg_uitvoer="$(cd "$repo" && ./install.sh 2>&1)"
zonder_arg_status=$?
[ "$zonder_arg_status" -eq 0 ] || fail "S84 — install.sh zonder argument faalde: $zonder_arg_uitvoer"
assert_contains "S84 — zonder argument meldt install.sh welke tag hij koos" "oude-versie" "$zonder_arg_uitvoer"

test_klaar
