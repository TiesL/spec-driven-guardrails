#!/usr/bin/env bash
# S9 — Verouderde adoptie meldt zichzelf.
# Dekt: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
# Dit scenario simuleert zelf de opeenvolging "geen skills -> wel skills, nog
# niet geïnstalleerd". Sinds W9 heeft de echte checkout een gevulde skills/,
# dus die eerst weghalen - anders start dit scenario al met de tweede
# toestand en test het zijn eigen eerste regel niet meer.
rm -rf "$repo/skills"
project="$(vers_project doelproject)"
CLAUDE_WORKFLOW_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1

# Vooraf: zonder skills-map in het repo hoort er niets gemeld te worden.
schoon="$SANDBOX/schoon.txt"
"$repo/pending-changes.sh" "$project" > "$schoon" 2>/dev/null
if grep -qi 'mist de skill' "$schoon"; then
  fail "S9 — melding verscheen terwijl dit repo helemaal geen skills heeft"
fi

# Given: het repo heeft skills, het project heeft ze niet geïnstalleerd.
mkdir -p "$repo/skills/pre-merge-review" "$repo/skills/deploy-guards"
echo "---" > "$repo/skills/pre-merge-review/SKILL.md"
echo "---" > "$repo/skills/deploy-guards/SKILL.md"

# When: een sessie start.
uitvoer="$SANDBOX/uitvoer.txt"
"$repo/pending-changes.sh" "$project" > "$uitvoer" 2>/dev/null
status=$?

# Then: de hook meldt dat adopt.sh opnieuw moet draaien.
grep -qi 'mist de skill' "$uitvoer" || {
  fail "S9 — geen melding over ontbrekende skills"
  cat "$uitvoer" >&2
}
grep -qi 'adopt.sh opnieuw' "$uitvoer" || fail "S9 — de melding zegt niet wat je moet doen"

# And: meerdere namen zijn van elkaar te onderscheiden. Zonder scheidingsteken
# is "deploy-guards pre merge review" niet te lezen als twee skills waarvan er
# één een spatie in zijn naam heeft.
# Alleen op de skills-regel kijken: de vraagteksten hierboven bevatten zelf
# komma's, dus een grep over de hele uitvoer zou altijd raak zijn.
skillregel="$(grep 'mist de skill' "$uitvoer")"
case "$skillregel" in
  *', '*) ;;
  *) fail "S9 — meerdere ontbrekende skills worden niet gescheiden: $skillregel" ;;
esac

# And: de ontbrekende skills staan er bij naam bij. Zonder die namen is de
# melding niet bruikbaar - je weet dan niet wát er mist of waarom.
for skill in pre-merge-review deploy-guards; do
  grep -q "$skill" "$uitvoer" || fail "S9 — de melding noemt de ontbrekende skill '$skill' niet"
done

# And: de sessie start gewoon door — een hook mag nooit blokkeren.
[ "$status" -eq 0 ] || fail "S9 — pending-changes.sh gaf status $status; dat blokkeert een sessie"

# Na installatie van de skills verdwijnt de melding weer.
mkdir -p "$project/.claude/skills"
ln -s "$repo/skills/pre-merge-review" "$project/.claude/skills/pre-merge-review"
ln -s "$repo/skills/deploy-guards" "$project/.claude/skills/deploy-guards"

na="$SANDBOX/na.txt"
"$repo/pending-changes.sh" "$project" > "$na" 2>/dev/null
if grep -qi 'mist de skill' "$na"; then
  fail "S9 — de melding blijft staan terwijl alle skills geïnstalleerd zijn"
fi

test_klaar
