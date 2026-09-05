#!/usr/bin/env bash
# S29 — De Wegwijzer lost elk verplaatst onderwerp in één sprong op.
# Dekt: F12

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

workflow="$TEST_REPO_ROOT/WORKFLOW.md"
[ -f "$workflow" ] || { fail "S29 — WORKFLOW.md ontbreekt"; test_klaar "S29"; }

alle_skills="$(cd "$TEST_REPO_ROOT/skills" 2>/dev/null && ls -d */ 2>/dev/null | sed 's#/$##')"

controleer_precies_een_rij() {
  local term="$1" verwachte_skill="$2"
  local rijen aantal skill
  rijen="$(wegwijzer_rijen "$workflow" | grep -i "$term" || true)"
  aantal="$(printf '%s\n' "$rijen" | grep -c . || true)"
  if [ "$aantal" -ne 1 ]; then
    fail "S29 — '$term' levert $aantal Wegwijzer-rijen op, 1 verwacht"
    return
  fi
  skill="$(skill_van_rij "$rijen")"
  printf '%s\n' "$alle_skills" | grep -qxF "$skill" \
    || fail "S29 — '$term' wijst naar '$skill', dat geen bestaande skill is"
  [ "$skill" = "$verwachte_skill" ] \
    || fail "S29 — '$term' wijst naar '$skill', '$verwachte_skill' verwacht"
}

controleer_precies_een_rij "kwaliteitsreview" "pre-merge-review"
controleer_precies_een_rij "onderbouwingsplicht" "adoption-registry"
controleer_precies_een_rij "adoptieregistratie" "adoption-registry"
controleer_precies_een_rij "deploy-guards" "deploy-guards"

# Onderbouwingsplicht en adoptieregistratie landen in dezelfde skill, maar
# horen twee eigen rijen te zijn, niet stilzwijgend één samengevoegde rij.
rij_onderbouwing="$(wegwijzer_rijen "$workflow" | grep -i "onderbouwingsplicht" || true)"
rij_adoptie="$(wegwijzer_rijen "$workflow" | grep -i "adoptieregistratie" || true)"
[ -z "$rij_onderbouwing" ] || [ -z "$rij_adoptie" ] || [ "$rij_onderbouwing" != "$rij_adoptie" ] \
  || fail "S29 — onderbouwingsplicht en adoptieregistratie delen dezelfde Wegwijzer-rij"

# Branching is niet verplaatst: geen Wegwijzer-rij nodig, de sectie blijft
# direct in WORKFLOW.md staan.
grep -qi '^## Branchstrategie' "$workflow" \
  || fail "S29 — 'Branchstrategie' staat niet meer direct in WORKFLOW.md"

test_klaar "S29"
