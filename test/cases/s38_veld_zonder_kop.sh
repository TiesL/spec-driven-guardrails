#!/usr/bin/env bash
# S38 — Een veld zonder voorafgaande kop levert geen entry.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een misvormde bron — een veld vóór de eerste kop.
bron="$SANDBOX/CHANGES.md"
cat > "$bron" <<'MD'
# Adopteerbare wijzigingen

- **Van toepassing als:** altijd

## echte-entry

- **Standaard:** ja
- **Van toepassing als:** altijd
MD

gezien="$SANDBOX/gezien.txt"
: > "$gezien"

# shellcheck disable=SC2329  # indirect aangeroepen, via itereer_entries
noteer() { printf '%s\n' "$1" >> "$gezien"; }

# When: itereer_entries die bron leest.
itereer_entries "$bron" noteer

# Then: alleen de entry ná de kop is gezien; het losse veld leverde niets op.
# wc -l, niet grep -c: een callback met een leeg ID schrijft een lege regel, en
# die moet juist meegeteld worden - dat is het geval dat dit scenario zoekt.
aantal="$(wc -l < "$gezien" | tr -d ' ')"
[ "$aantal" -eq 1 ] || fail "S38 — $aantal callbacks, 1 verwacht (veld zonder kop is meegeteld)"
grep -qx 'echte-entry' "$gezien" || fail "S38 — de entry na de kop is niet verwerkt"

# And: er is geen aanroep met een leeg ID geweest.
if grep -qx '' "$gezien"; then
  fail "S38 — callback aangeroepen met een leeg ID"
fi

# And: hetzelfde geldt via adopt.sh zelf. De guard zat vóór W4 alleen in
# pending-changes.sh; adopt.sh produceerde bij zo'n misvormde bron een rij met
# een leeg ID. Deze controle loopt via het echte script in plaats van via de
# bibliotheek, want geseede_ids() filtert op '^| [a-z]' en zou een lege-ID-rij
# nooit zien.
nep="$SANDBOX/nepworkflow"
mkdir -p "$nep/lib" "$nep/templates"
cp "$TEST_REPO_ROOT/lib/changes.sh" "$nep/lib/"
cp "$TEST_REPO_ROOT/adopt.sh" "$nep/"
echo "# Werkwijze" > "$nep/WORKFLOW.md"
cp "$bron" "$nep/CHANGES.md"

project="$(vers_project doelproject)"
SPEC_DRIVEN_GUARDRAILS_DIR="$nep" "$nep/adopt.sh" "$project" >/dev/null 2>&1

tabel="$project/WORKFLOW-ADOPTIE.md"
if [ -f "$tabel" ] && grep -qE '^\| *\|' "$tabel"; then
  fail "S38 — adopt.sh schreef een rij met een leeg ID"
  grep -nE '^\| *\|' "$tabel" >&2
fi

test_klaar
