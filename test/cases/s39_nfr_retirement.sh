#!/usr/bin/env bash
# S39 — Een geretireerd kenmerk verdwijnt uit beide consumenten.
# Dekt: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
project="$(vers_project doelproject)"

# spec-portability heeft `Standaard: vraag`, dus hij staat na een verse adoptie
# open. Dat is de controlewaarde.
CLAUDE_WORKFLOW_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1
# Uitvoer eerst vastleggen: `... | grep -q` sluit de pijp bij de eerste treffer,
# waarna de producent SIGPIPE krijgt en de pijplijn onder `pipefail` non-nul
# geeft terwijl de treffer er wél was.
voor="$SANDBOX/voor.txt"
"$repo/pending-changes.sh" "$project" > "$voor" 2>/dev/null
if ! grep -q 'spec-portability' "$voor"; then
  fail "S39 — spec-portability stond niet open; opzet deugt niet"
  test_klaar
fi

# Given: dat kenmerk krijgt status: geretireerd.
sed -i.bak 's/^status: actief$/status: geretireerd/' "$repo/nfr/spec-portability.md"
rm -f "$repo/nfr/spec-portability.md.bak"

# When/Then: het wordt niet meer gevraagd.
na="$SANDBOX/na.txt"
"$repo/pending-changes.sh" "$project" > "$na" 2>/dev/null
if grep -q 'spec-portability' "$na"; then
  fail "S39 — spec-portability wordt nog gevraagd na retirement"
fi

# En de vraagtekst hoort erbij te staan zolang het kenmerk actief is: zonder
# vraag is een openstaande melding onbruikbaar voor wie hem moet beantwoorden.
if ! grep -q 'spec-portability — .' "$voor"; then
  fail "S39 — spec-portability werd gemeld zonder vraagtekst"
  grep 'spec-portability' "$voor" >&2
fi

# And: het staat niet meer in het gegenereerde blok.
# shellcheck source=../../lib/nfr.sh
. "$repo/lib/nfr.sh"
blok="$SANDBOX/blok.txt"
nfr_blok "$repo/nfr" > "$blok"
if grep -q 'spec-portability' "$blok"; then
  fail "S39 — spec-portability staat nog in het gegenereerde blok"
fi

# And: na regenereren klaagt check niet meer over drift.
if "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S39 — check klaagde niet, terwijl het sjabloon nog het oude blok bevat"
fi
(cd "$repo" && ./genereer-prd-blok >/dev/null 2>&1)
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S39 — check klaagt nog na regenereren"
  "$repo/check" --no-tests "$repo" 2>&1 | grep -E 'FOUT|betreft' >&2
fi

test_klaar
