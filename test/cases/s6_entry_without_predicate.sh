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
# Adoptable changes

## forgotten-entry

- **Question:** Something nobody attached a predicate to?
- **Default:** yes

## real-entry

- **Default:** yes
- **Applies if:** always

## forgotten-after-good

- **Question:** Forgotten predicate, but after an entry that does have one?

## another-good-one

- **Applies if:** always

## forgotten-as-last

- **Question:** Forgotten predicate, as the last one in the file?
MD

seen="$SANDBOX/seen.txt"
: > "$seen"
# shellcheck disable=SC2329  # called indirectly, via iterate_entries
record() { printf '%s\n' "$1" >> "$seen"; }

# When: the shared parser reads that source.
message="$SANDBOX/message.txt"
iterate_entries "$source" record 2>"$message"
status=$?

# Then: a warning appears that names the ID.
grep -q 'forgotten-entry' "$message" || {
  fail "S6 — no warning naming 'forgotten-entry'"
  cat "$message" >&2
}
grep -qi 'warning' "$message" || fail "S6 — the message is not recognizable as a warning"

# And: the entry is not seeded or asked about.
if grep -qx 'forgotten-entry' "$seen"; then
  fail "S6 — forgotten-entry still produced a callback"
fi
grep -qx 'real-entry' "$seen" || fail "S6 — the entry with a predicate was not processed"

# And: a broken entry after a good one is also reported. The parser state
# must not carry over from the previous entry.
grep -q 'forgotten-after-good' "$message" || fail "S6 — no warning for a broken entry after a good one"

# And: also when it is the last one in the file — then there is no
# following heading left to trigger the check.
grep -q 'forgotten-as-last' "$message" || fail "S6 — no warning for a broken entry as the last one in the file"

# And the good entries are all processed.
grep -qx 'another-good-one' "$seen" || fail "S6 — another-good-one was not processed"

# And: the warning blocks nothing.
[ "$status" -eq 0 ] || fail "S6 — iterate_entries gave status $status; a warning must not block"

# And: a source without a trailing newline does not lose its last line.
without_nl="$SANDBOX/without-newline.md"
printf '# K\n\n## last-entry\n\n- **Applies if:** always' > "$without_nl"
seen2="$SANDBOX/seen2.txt"
: > "$seen2"
# shellcheck disable=SC2329  # called indirectly, via iterate_entries
record2() { printf '%s\n' "$1" >> "$seen2"; }
message2="$SANDBOX/message2.txt"
iterate_entries "$without_nl" record2 2>"$message2"
grep -qx 'last-entry' "$seen2" || fail "S6 — the last entry disappeared due to a missing trailing newline"
if grep -q 'last-entry' "$message2"; then
  fail "S6 — misleading warning for an entry that does have a predicate"
fi

# And the real CHANGES.md is clean: not a single heading without a predicate.
real_message="$SANDBOX/real.txt"
iterate_entries "$TEST_REPO_ROOT/CHANGES.md" record 2>"$real_message" >/dev/null
if grep -qi 'warning' "$real_message"; then
  fail "S6 — the real CHANGES.md produces warnings:"
  cat "$real_message" >&2
fi

test_done
