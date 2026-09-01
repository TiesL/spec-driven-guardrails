#!/usr/bin/env bash
# S40 — De volgorde van het sjabloonblok ligt vast.
# Dekt: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: het volgorde-veld bepaalt de plek in het blok. Twee kenmerken wisselen.
een="$repo/nfr/spec-security.md"        # volgorde: 1
twee="$repo/nfr/spec-data-integriteit.md" # volgorde: 2
sed -i.bak 's/^volgorde: 1$/volgorde: 2/' "$een"
sed -i.bak 's/^volgorde: 2$/volgorde: 1/' "$twee"
rm -f "$repo"/nfr/*.bak

# When: het ingecheckte blok staat nog in de oude volgorde.
# Then: check faalt. Een vergelijking die op ID sorteert ziet dit niet, dus de
# volgorde wordt apart getoetst.
uitvoer="$("$repo/check" --no-tests "$repo" 2>&1)"
status=$?

if [ "$status" -eq 0 ]; then
  fail "S40 — check slaagde terwijl de blokvolgorde afwijkt"
fi
assert_contains "S40" "volgorde" "$uitvoer"

# En na regenereren is het weer in orde.
(cd "$repo" && ./genereer-prd-blok >/dev/null 2>&1)
"$repo/check" --no-tests "$repo" >/dev/null 2>&1 || fail "S40 — check klaagt nog na regenereren"

test_klaar
