#!/usr/bin/env bash
# S25 — De user-level skill staat op userniveau.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project s25)"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1

doel="$HOME/.claude/skills/adopt-workflow/SKILL.md"
[ -f "$doel" ] || fail "S25 — $doel bestaat niet na 'adopt.sh --user'"

# F10: adopt-workflow is de énige user-level skill. Niet alleen "bestaat", ook
# "er staat verder niets" - anders is dit geen echte controle.
aantal="$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
[ "$aantal" -eq 1 ] \
  || fail "S25 — \$HOME/.claude/skills bevat $aantal item(s), 1 verwacht (alleen adopt-workflow)"

[ ! -e "$project/.claude" ] \
  || fail "S25 — het (niet-geadopteerde) project kreeg een .claude-map, terwijl adopt-workflow userbreed hoort te landen"

# Tweede run: idempotent, geen kapotte link.
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1
[ -f "$doel" ] || fail "S25 — een tweede '--user'-run liet de skill niet bestaan"

# --- Regressie: een verweesde link blijft opruimbaar, ook als de skill zelf
# inmiddels weg is uit de bron. Zonder dit meldt élke sessie in élk project
# een laadfout, want de vorige installatie liet een dode link achter.
kaal="$(sandbox_copy_repo kaal)"
rm -rf "$HOME/.claude"
SPEC_DRIVEN_GUARDRAILS_DIR="$kaal" "$kaal/adopt.sh" --user >/dev/null 2>&1
[ -L "$HOME/.claude/skills/adopt-workflow" ] \
  || fail "S25 — voorbereidende installatie (kale kopie) legde geen symlink aan"

rm -rf "$kaal/skills/adopt-workflow"
SPEC_DRIVEN_GUARDRAILS_DIR="$kaal" "$kaal/adopt.sh" --user >/dev/null 2>&1
if [ -e "$HOME/.claude/skills/adopt-workflow" ] || [ -L "$HOME/.claude/skills/adopt-workflow" ]; then
  fail "S25 — een verweesde adopt-workflow-link op userniveau is niet opgeruimd nadat de bron verdween"
fi

# --- Regressie: een eigen ~/.claude/skills-symlink van de gebruiker blijft
# heel. Dit is de hele persoonlijke skill-namespace op deze machine, niet iets
# van dit repo - "bij twijfel niets weggooien" geldt hier sterker dan in een
# project.
rm -rf "$HOME/.claude"
mkdir -p "$SANDBOX/elders-skills/eigen-skill"
echo "# van de gebruiker zelf" > "$SANDBOX/elders-skills/eigen-skill/SKILL.md"
mkdir -p "$HOME/.claude"
ln -s "$SANDBOX/elders-skills" "$HOME/.claude/skills"

SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1

[ -L "$HOME/.claude/skills" ] \
  || fail "S25 — een eigen ~/.claude/skills-symlink van de gebruiker is vervangen door een echte map"
bestemming="$(readlink "$HOME/.claude/skills")"
[ "$bestemming" = "$SANDBOX/elders-skills" ] \
  || fail "S25 — de eigen ~/.claude/skills-symlink wijst niet meer naar dezelfde plek"
[ -f "$SANDBOX/elders-skills/eigen-skill/SKILL.md" ] \
  || fail "S25 — de inhoud achter de eigen symlink is verdwenen"
[ -f "$SANDBOX/elders-skills/adopt-workflow/SKILL.md" ] \
  || fail "S25 — adopt-workflow is niet geïnstalleerd binnen de eigen symlink-bestemming"

test_klaar "S25"
