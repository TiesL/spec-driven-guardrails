#!/usr/bin/env bash
# S31 — Blocking-edges staan in beide issue-templates.
#
# De velden moeten machineleesbaar zijn, niet alleen aanwezig: aan regelbegin en
# in de `**Veld:**`-vorm die de bestaande issues al gebruiken. Een variant als
# `- Blocked by:` leest voor een mens hetzelfde en is voor een grep iets anders,
# en dan levert de conventie geen graaf op maar een gevoel.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

repo="$TEST_REPO_ROOT"

for sjabloon in work-item epic; do
  pad="$repo/templates/ISSUE_TEMPLATE/$sjabloon.md"
  [ -f "$pad" ] || fail "S31 — $sjabloon.md ontbreekt"

  for veld in "Blocked by" "Blocks"; do
    grep -q "^\*\*$veld:\*\*" "$pad" \
      || fail "S31 — $sjabloon.md heeft geen '**$veld:**' aan regelbegin"
  done
done

# AC2: het veld moet een `#<nummer>`-token kunnen dragen. Het sjabloon toont dat
# met een kaal `#`; de controle hieronder eist de vorm, niet een verzonnen nummer.
for sjabloon in work-item epic; do
  pad="$repo/templates/ISSUE_TEMPLATE/$sjabloon.md"
  regel="$(grep '^\*\*Blocked by:\*\*' "$pad")"
  case "$regel" in
    *"#"*) ;;
    *) fail "S31 — $sjabloon.md: '$regel' laat niet zien dat er een #-nummer in hoort" ;;
  esac
done

# AC3: adopt.sh ververst de sjablonen in een project, ook als er al een oudere
# versie ligt. Zonder dat blijft de conventie in dit repo hangen.
sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project met-oud-sjabloon)"
mkdir -p "$project/.github/ISSUE_TEMPLATE"
echo "verouderd sjabloon zonder velden" > "$project/.github/ISSUE_TEMPLATE/work-item.md"

adopteer "$project"

grep -q '^\*\*Blocked by:\*\*' "$project/.github/ISSUE_TEMPLATE/work-item.md" \
  || fail "S31 — adopt.sh ververste het verouderde sjabloon niet"

test_klaar "S31"
