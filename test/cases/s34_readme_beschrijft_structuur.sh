#!/usr/bin/env bash
# S34 — De README beschrijft de nieuwe structuur.
# Dekt: F16

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

readme="$TEST_REPO_ROOT/README.md"

for map in 'skills/' 'hooks/' 'lib/' 'nfr/' 'test/' 'CHANGES-ARCHIEF.md'; do
  if ! grep -qF "\`$map\`" "$readme"; then
    fail "S34 — README.md noemt \`$map\` niet in de inhoudstabel"
  fi
done

# "check" komt ook los voor in doorlopende tekst; de tabelrij zelf is wat telt.
if ! grep -qE '^\| `check` \|' "$readme"; then
  fail "S34 — README.md heeft geen tabelrij voor \`check\`"
fi

if ! grep -q 'vijftien niet-functionele vragen' "$readme"; then
  fail "S34 — README.md noemt niet 'vijftien niet-functionele vragen'"
fi
if grep -q 'vijf niet-functionele vragen' "$readme"; then
  fail "S34 — README.md noemt nog steeds 'vijf niet-functionele vragen' (verouderd sinds 4821bac)"
fi

test_klaar
