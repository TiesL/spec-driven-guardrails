#!/usr/bin/env bash
# S5 — Generator en ingecheckt sjabloon lopen niet uit de pas.
# Dekt: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Vooraf: op de ingecheckte toestand hoort check hier niet over te klagen.
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S5 — check klaagt al op de ongewijzigde toestand"
fi

# Given: een nfr/*.md waarvan de Invulhulp is gewijzigd zonder te regenereren.
doel="$repo/nfr/spec-security.md"
if [ ! -f "$doel" ]; then
  fail "S5 — nfr/spec-security.md ontbreekt"
  test_klaar
fi

python3 - "$doel" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
kop = "## Invulhulp"
i = s.index(kop) + len(kop)
open(p, "w").write(s[:i] + "\nEen bewust afwijkende invulhulp voor deze test.\n")
PY

# When: ./check draait.
uitvoer="$("$repo/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, met de betreffende NFR in de melding.
if [ "$status" -eq 0 ]; then
  fail "S5 — check slaagde terwijl register en sjabloon uit de pas lopen"
fi
assert_contains "S5" "spec-security" "$uitvoer"

test_klaar
