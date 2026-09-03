#!/usr/bin/env bash
# S49 — Een eigen ci.yml wordt niet overschreven; de afwijking wordt zichtbaar
# via de adoptieregistratie in plaats van via een stille kopie.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een project met een package.json — anders scaffoldt adopt.sh sowieso
# geen workflow — en een handgeschreven ci.yml die afwijkt van het sjabloon.
project="$(vers_project eigen-ci)"
echo '{"name":"t"}' > "$project/package.json"
mkdir -p "$project/.github/workflows"
eigen='name: Eigen CI die niet van het sjabloon komt'
echo "$eigen" > "$project/.github/workflows/ci.yml"

# When: adopt.sh draait, twee keer.
adopteer "$project"
na_een="$(cat "$project/.github/workflows/ci.yml")"
adopteer "$project"
na_twee="$(cat "$project/.github/workflows/ci.yml")"

# Then: het bestand is ongemoeid gebleven.
[ "$na_een" = "$eigen" ] || fail "S49 — adopt.sh overschreef een eigen ci.yml"

# And: twee keer draaien geeft hetzelfde resultaat.
[ "$na_twee" = "$na_een" ] || fail "S49 — adopt.sh is niet idempotent op ci.yml"

# And: de afwijking blijft niet onzichtbaar. Het sjabloon repareren helpt alleen
# nieuwe projecten; bestaande houden hun eigen workflow. Daarom stelt de
# adoptieregistratie de vraag — dat is het mechanisme dat een stille afwijking
# hoorbaar maakt, niet een melding in adopt.sh die één keer voorbijkomt.
tabel="$project/WORKFLOW-ADOPTIE.md"
grep -q '^| ci-op-pr-en-main ' "$tabel" \
  || fail "S49 — ci-op-pr-en-main staat niet in de adoptietabel van een project met package.json"

# And: voor een project zonder package.json is de vraag niet van toepassing —
# dezelfde afbakening als ci-conventie, waar deze entry op voortbouwt.
kaal="$(vers_project zonder-package-json)"
adopteer "$kaal"
if grep -q '^| ci-op-pr-en-main ' "$kaal/WORKFLOW-ADOPTIE.md"; then
  fail "S49 — ci-op-pr-en-main is geseed in een project zonder package.json"
fi

test_klaar
