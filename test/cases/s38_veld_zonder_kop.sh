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

test_klaar
