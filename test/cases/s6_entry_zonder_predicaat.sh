#!/usr/bin/env bash
# S6 — Een entry zonder `Van toepassing als` levert een waarschuwing.
# Dekt: F5

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een bron met een ## -kop zonder Van toepassing als-veld.
bron="$SANDBOX/CHANGES.md"
cat > "$bron" <<'MD'
# Adopteerbare wijzigingen

## vergeten-entry

- **Vraag:** Iets waar niemand een predicaat bij zette?
- **Standaard:** ja

## echte-entry

- **Standaard:** ja
- **Van toepassing als:** altijd
MD

gezien="$SANDBOX/gezien.txt"
: > "$gezien"
# shellcheck disable=SC2329  # indirect aangeroepen, via itereer_entries
noteer() { printf '%s\n' "$1" >> "$gezien"; }

# When: de gedeelde parser die bron leest.
melding="$SANDBOX/melding.txt"
itereer_entries "$bron" noteer 2>"$melding"
status=$?

# Then: er verschijnt een waarschuwing die het ID noemt.
grep -q 'vergeten-entry' "$melding" || {
  fail "S6 — geen waarschuwing die 'vergeten-entry' noemt"
  cat "$melding" >&2
}
grep -qi 'waarschuwing' "$melding" || fail "S6 — de melding is niet als waarschuwing herkenbaar"

# And: de entry wordt niet geseed of gevraagd.
if grep -qx 'vergeten-entry' "$gezien"; then
  fail "S6 — vergeten-entry leverde toch een callback op"
fi
grep -qx 'echte-entry' "$gezien" || fail "S6 — de entry mét predicaat is niet verwerkt"

# And: de waarschuwing blokkeert niets.
[ "$status" -eq 0 ] || fail "S6 — itereer_entries gaf status $status; een waarschuwing mag niet blokkeren"

# En de echte CHANGES.md is schoon: geen enkele kop zonder predicaat.
echte_melding="$SANDBOX/echt.txt"
itereer_entries "$TEST_REPO_ROOT/CHANGES.md" noteer 2>"$echte_melding" >/dev/null
if grep -qi 'waarschuwing' "$echte_melding"; then
  fail "S6 — de echte CHANGES.md levert waarschuwingen op:"
  cat "$echte_melding" >&2
fi

test_klaar
