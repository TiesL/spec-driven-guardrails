#!/usr/bin/env bash
# S37 — Predicaat- en parserlogica staat op precies één plek.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

bibliotheek="$TEST_REPO_ROOT/lib/changes.sh"

if [ ! -f "$bibliotheek" ]; then
  fail "S37 — lib/changes.sh ontbreekt"
  test_klaar
fi

# Then: de aanroepers bevatten geen eigen predicaattak of koploper meer.
for script in adopt.sh pending-changes.sh; do
  pad="$TEST_REPO_ROOT/$script"

  for patroon in 'heeft-package-json)' 'heeft-deploy-script)'; do
    if grep -q -- "$patroon" "$pad"; then
      fail "S37 — $script bevat weer een eigen predicaattak: $patroon"
    fi
  done

  # De koploper van de parser: een case-tak op '## '. De bibliotheek hoort de
  # enige plek te zijn die CHANGES.md regel voor regel uit elkaar haalt.
  if grep -q "'## '\*)" "$pad"; then
    fail "S37 — $script bevat weer een eigen CHANGES.md-parser"
  fi

  grep -q 'lib/changes.sh' "$pad" || fail "S37 — $script sourcet de bibliotheek niet"
done

# And: de bibliotheek bevat ze wél. Zonder deze controle zou de test ook slagen
# als iemand lib/changes.sh leeghaalt.
for patroon in 'heeft-package-json)' 'heeft-deploy-script)' "'## '\*)"; do
  grep -q -- "$patroon" "$bibliotheek" || fail "S37 — lib/changes.sh mist: $patroon"
done

test_klaar
