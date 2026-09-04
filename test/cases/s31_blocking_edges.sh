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

# Het sjabloon zonder zijn HTML-commentaar. Een veld dat per ongeluk binnen
# `<!-- ... -->` belandt staat er voor een grep gewoon, maar bereikt het issue
# nooit — dan verstopt het sjabloon precies wat het moet voorschrijven.
zonder_commentaar() {
  awk '/<!--/ { in_c = 1 } !in_c; /-->/ { in_c = 0 }' "$1"
}

for sjabloon in work-item epic; do
  pad="$repo/templates/ISSUE_TEMPLATE/$sjabloon.md"
  [ -f "$pad" ] || fail "S31 — $sjabloon.md ontbreekt"

  zichtbaar="$(zonder_commentaar "$pad")"

  for veld in "Blocked by" "Blocks"; do
    regel="$(printf '%s\n' "$zichtbaar" | grep "^\*\*$veld:\*\*" || true)"

    [ -n "$regel" ] \
      || fail "S31 — $sjabloon.md heeft geen '**$veld:**' aan regelbegin, buiten commentaar"

    # AC2: het veld moet een `#<nummer>`-token kunnen dragen. Het sjabloon toont
    # dat met een kaal `#`; de controle eist de vorm, niet een verzonnen nummer.
    # Beide velden, niet alleen het eerste — een controle die maar één van twee
    # velden ziet, dekt de helft van wat hij beweert.
    case "$regel" in
      *"#"*) ;;
      *) fail "S31 — $sjabloon.md: '$regel' laat niet zien dat er een #-nummer in hoort" ;;
    esac
  done
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
