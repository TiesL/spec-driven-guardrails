#!/usr/bin/env bash
# S6 — An entry without `Van toepassing als` produces a warning.
# Dekt: F5

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a source with a ## heading without a Van toepassing als field.
bron="$SANDBOX/CHANGES.md"
cat > "$bron" <<'MD'
# Adopteerbare wijzigingen

## vergeten-entry

- **Vraag:** Iets waar niemand een predicaat bij zette?
- **Standaard:** ja

## echte-entry

- **Standaard:** ja
- **Van toepassing als:** altijd

## vergeten-na-goede

- **Vraag:** Vergeten predicaat, maar dan ná een entry die er wél een heeft?

## nog-een-goede

- **Van toepassing als:** altijd

## vergeten-als-laatste

- **Vraag:** Vergeten predicaat, als laatste in het bestand?
MD

gezien="$SANDBOX/gezien.txt"
: > "$gezien"
# shellcheck disable=SC2329  # called indirectly, via itereer_entries
noteer() { printf '%s\n' "$1" >> "$gezien"; }

# When: the shared parser reads that source.
melding="$SANDBOX/melding.txt"
itereer_entries "$bron" noteer 2>"$melding"
status=$?

# Then: a warning appears that names the ID.
grep -q 'vergeten-entry' "$melding" || {
  fail "S6 — no warning naming 'vergeten-entry'"
  cat "$melding" >&2
}
grep -qi 'waarschuwing' "$melding" || fail "S6 — the message is not recognizable as a warning"

# And: the entry is not seeded or asked about.
if grep -qx 'vergeten-entry' "$gezien"; then
  fail "S6 — vergeten-entry still produced a callback"
fi
grep -qx 'echte-entry' "$gezien" || fail "S6 — the entry with a predicate was not processed"

# And: a broken entry after a good one is also reported. The parser state
# must not carry over from the previous entry.
grep -q 'vergeten-na-goede' "$melding" || fail "S6 — no warning for a broken entry after a good one"

# And: also when it is the last one in the file — then there is no
# following heading left to trigger the check.
grep -q 'vergeten-als-laatste' "$melding" || fail "S6 — no warning for a broken entry as the last one in the file"

# And the good entries are all processed.
grep -qx 'nog-een-goede' "$gezien" || fail "S6 — nog-een-goede was not processed"

# And: the warning blocks nothing.
[ "$status" -eq 0 ] || fail "S6 — itereer_entries gave status $status; a warning must not block"

# And: a source without a trailing newline does not lose its last line.
zonder_nl="$SANDBOX/zonder-newline.md"
printf '# K\n\n## laatste-entry\n\n- **Van toepassing als:** altijd' > "$zonder_nl"
gezien2="$SANDBOX/gezien2.txt"
: > "$gezien2"
# shellcheck disable=SC2329  # called indirectly, via itereer_entries
noteer2() { printf '%s\n' "$1" >> "$gezien2"; }
melding2="$SANDBOX/melding2.txt"
itereer_entries "$zonder_nl" noteer2 2>"$melding2"
grep -qx 'laatste-entry' "$gezien2" || fail "S6 — the last entry disappeared due to a missing trailing newline"
if grep -q 'laatste-entry' "$melding2"; then
  fail "S6 — misleading warning for an entry that does have a predicate"
fi

# And the real CHANGES.md is clean: not a single heading without a predicate.
echte_melding="$SANDBOX/echt.txt"
itereer_entries "$TEST_REPO_ROOT/CHANGES.md" noteer 2>"$echte_melding" >/dev/null
if grep -qi 'waarschuwing' "$echte_melding"; then
  fail "S6 — the real CHANGES.md produces warnings:"
  cat "$echte_melding" >&2
fi

test_klaar
