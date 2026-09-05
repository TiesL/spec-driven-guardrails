#!/usr/bin/env bash
# R7 — Geadopteerd project blijft de volledige operationele instructie zien.
# Dekt: F12
#
# De vijf termen (branching, kwaliteitsreview, onderbouwingsplicht,
# deploy-guards, adoptieregistratie) moeten na de knip van WORKFLOW.md nog
# steeds in één sprong oplosbaar zijn: direct in het bestand, of via een
# expliciete verwijzing naar een skill die ook echt bestaat.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project r7)"
adopteer "$project"

claude_md="$project/CLAUDE.md"
[ -f "$claude_md" ] || { fail "R7 — CLAUDE.md ontbreekt na adoptie"; test_klaar "R7"; }

controleer_term() {
  local term="$1"
  local rijen aantal skill doel
  rijen="$(wegwijzer_rijen "$claude_md" | grep -i "$term" || true)"
  aantal="$(printf '%s\n' "$rijen" | grep -c . || true)"
  [ "$aantal" -ge 1 ] || { fail "R7 — '$term' levert geen Wegwijzer-rij op"; return; }
  while IFS= read -r rij; do
    [ -n "$rij" ] || continue
    skill="$(skill_van_rij "$rij")"
    doel="$project/.claude/skills/$skill/SKILL.md"
    [ -f "$doel" ] \
      || fail "R7 — '$term' wijst naar skill '$skill', maar $doel bestaat niet"
  done <<< "$rijen"
}

controleer_term "kwaliteitsreview"
controleer_term "onderbouwingsplicht"
controleer_term "deploy-guards"
controleer_term "adoptieregistratie"

# Branching is niet verplaatst: de sectie blijft direct in het bestand.
grep -qi '^## Branchstrategie' "$claude_md" \
  || fail "R7 — 'Branchstrategie' staat niet meer direct in CLAUDE.md"

test_klaar "R7"
