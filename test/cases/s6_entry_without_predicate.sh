#!/usr/bin/env bash
# S6 — An entry without `Applies if` produces a warning.
# Covers: F5

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a source with a ## heading without an Applies if field.
source="$SANDBOX/CHANGES.md"
cat > "$source" <<'MD'
# Adopteerbare wijzigingen

## vergeten-entry

- **Question:** Iets waar niemand een predicaat bij zette?
- **Default:** yes

## echte-entry

- **Default:** yes
- **Applies if:** always

## vergeten-na-goede

- **Question:** Vergeten predicaat, maar dan ná een entry die er wél een heeft?

## nog-een-goede

- **Applies if:** always

## vergeten-als-laatste

- **Question:** Vergeten predicaat, als laatste in het bestand?
MD

seen="$SANDBOX/seen.txt"
: > "$seen"
# shellcheck disable=SC2329  # called indirectly, via iterate_entries
noteer() { printf '%s\n' "$1" >> "$seen"; }

# When: the shared parser reads that source.
message="$SANDBOX/message.txt"
iterate_entries "$source" noteer 2>"$message"
status=$?

# Then: a warning appears that names the ID.
grep -q 'vergeten-entry' "$message" || {
  fail "S6 — no warning naming 'vergeten-entry'"
  cat "$message" >&2
}
grep -qi 'warning' "$message" || fail "S6 — the message is not recognizable as a warning"

# And: the entry is not seeded or asked about.
if grep -qx 'vergeten-entry' "$seen"; then
  fail "S6 — vergeten-entry still produced a callback"
fi
grep -qx 'echte-entry' "$seen" || fail "S6 — the entry with a predicate was not processed"

# And: a broken entry after a good one is also reported. The parser state
# must not carry over from the previous entry.
grep -q 'vergeten-na-goede' "$message" || fail "S6 — no warning for a broken entry after a good one"

# And: also when it is the last one in the file — then there is no
# following heading left to trigger the check.
grep -q 'vergeten-als-laatste' "$message" || fail "S6 — no warning for a broken entry as the last one in the file"

# And the good entries are all processed.
grep -qx 'nog-een-goede' "$seen" || fail "S6 — nog-een-goede was not processed"

# And: the warning blocks nothing.
[ "$status" -eq 0 ] || fail "S6 — iterate_entries gave status $status; a warning must not block"

# And: a source without a trailing newline does not lose its last line.
without_nl="$SANDBOX/zonder-newline.md"
printf '# K\n\n## laatste-entry\n\n- **Applies if:** always' > "$without_nl"
gezien2="$SANDBOX/gezien2.txt"
: > "$gezien2"
# shellcheck disable=SC2329  # called indirectly, via iterate_entries
noteer2() { printf '%s\n' "$1" >> "$gezien2"; }
melding2="$SANDBOX/melding2.txt"
iterate_entries "$without_nl" noteer2 2>"$melding2"
grep -qx 'laatste-entry' "$gezien2" || fail "S6 — the last entry disappeared due to a missing trailing newline"
if grep -q 'laatste-entry' "$melding2"; then
  fail "S6 — misleading warning for an entry that does have a predicate"
fi

# And the real CHANGES.md is clean: not a single heading without a predicate.
real_message="$SANDBOX/echt.txt"
iterate_entries "$TEST_REPO_ROOT/CHANGES.md" noteer 2>"$real_message" >/dev/null
if grep -qi 'warning' "$real_message"; then
  fail "S6 — the real CHANGES.md produces warnings:"
  cat "$real_message" >&2
fi

test_done
