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
project="$(vers_project doelproject)"
CLAUDE_WORKFLOW_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1

# Vooraf: zonder skills-map in het repo hoort er niets gemeld te worden.
schoon="$SANDBOX/schoon.txt"
"$repo/pending-changes.sh" "$project" > "$schoon" 2>/dev/null
if grep -qi 'adopt.sh opnieuw' "$schoon"; then
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
grep -qi 'verouderde adoptie' "$uitvoer" || {
  fail "S9 — geen melding over een verouderde adoptie"
  cat "$uitvoer" >&2
}
grep -qi 'adopt.sh opnieuw' "$uitvoer" || fail "S9 — de melding zegt niet wat je moet doen"

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
if grep -qi 'adopt.sh opnieuw' "$na"; then
  fail "S9 — de melding blijft staan terwijl alle skills geïnstalleerd zijn"
fi

test_klaar
