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

# And: beide scripts roepen de bibliotheekfunctie ook daadwerkelijk aan. De
# controles hierboven zoeken op tekst en zien dus alleen letterlijke kopieen;
# logica die in een andere vorm is herschreven — een if-keten in plaats van een
# case — zou er ongemerkt doorheen glippen. Deze controle is gedragsmatig: de
# functie wordt geinstrumenteerd en er wordt vastgesteld dat hij is aangeroepen.
sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
log="$SANDBOX/aanroepen.txt"

cat >> "$repo/lib/changes.sh" <<INSTR

# --- alleen voor S37: legt vast dat deze functie is aangeroepen ---
predicaat_waar() {
  printf '%s\n' "\$1" >> "$log"
  case "\$1" in
    altijd) return 0 ;;
    heeft-package-json) [ -f "\$2/package.json" ] ;;
    heeft-deploy-script)
      [ -f "\$2/package.json" ] && grep -q '"deploy"[[:space:]]*:' "\$2/package.json" ;;
    *) return 1 ;;
  esac
}
INSTR

project="$(vers_project doelproject)"

: > "$log"
SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1
if [ ! -s "$log" ]; then
  fail "S37 — adopt.sh riep predicaat_waar uit de bibliotheek niet aan"
fi

: > "$log"
"$repo/pending-changes.sh" "$project" >/dev/null 2>&1
if [ ! -s "$log" ]; then
  fail "S37 — pending-changes.sh riep predicaat_waar uit de bibliotheek niet aan"
fi

test_klaar
