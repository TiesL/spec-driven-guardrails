#!/usr/bin/env bash
# S43 — Een gezonde bron levert niets op stderr.
# Dekt: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Deze controle bestaat omdat de hook stderr naar /dev/null stuurt en élke
# andere test dat ook doet. Een shellfout in het script bleef daardoor
# structureel onzichtbaar — er ging er één dagelijks af in drie van de vier
# echte projecten zonder dat iets klaagde.
controleer() {
  local omschrijving="$1" pad="$2"
  local fout="$SANDBOX/stderr.txt"
  "$TEST_REPO_ROOT/pending-changes.sh" "$pad" > /dev/null 2> "$fout"
  if [ -s "$fout" ]; then
    fail "S43 — $omschrijving levert uitvoer op stderr:"
    sed 's/^/      /' "$fout" >&2
  fi
}

# De vier bevroren nulmetingen: een echte doorsnede van wat er in de praktijk
# staat, inclusief een project zonder adoptietabel.
for project in a2t-emails tennis-admin tennis-registration tennis-invoicing; do
  controleer "fixture $project" "$TEST_REPO_ROOT/test/fixtures/nulmeting/$project"
done

# Vers geadopteerd: alle rijen dragen nog een voorlopige stempel.
vers="$(vers_project vers)"
adopteer "$vers"
controleer "vers geadopteerd project" "$vers"

# Alles onderbouwd: nul wachtende rijen. Dat is precies de grens waar het
# tellen misging.
sed -i.bak 's/bij adoptie — vereist onderbouwing tijdens PRD\/architectuur/onderbouwd/g' \
  "$vers/WORKFLOW-ADOPTIE.md"
rm -f "$vers/WORKFLOW-ADOPTIE.md.bak"
controleer "project zonder wachtende onderbouwingen" "$vers"

# En een project dat nooit geadopteerd is.
kaal="$(vers_project kaal)"
controleer "niet-geadopteerd project" "$kaal"

test_klaar
