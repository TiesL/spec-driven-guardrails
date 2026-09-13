#!/usr/bin/env bash
# S7 — The signal counts rows still waiting on substantiation.
# Covers: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a freshly adopted project with 21 seeded rows carrying "requires
# substantiation".
project="$(fresh_project target-project)"
adopt "$project"

rows="$(grep -c 'requires substantiation' "$project/WORKFLOW-ADOPTION.md")"
[ "$rows" -eq 21 ] || fail "S7 — $rows rows with 'requires substantiation', 21 expected"

# When: pending-changes.sh runs.
output="$SANDBOX/output.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$output" 2>/dev/null

# Then: a message appears with the count.
grep -q '21 row(s)' "$output" || {
  fail "S7 — no message with the count of pending substantiations"
  cat "$output" >&2
}
grep -qi 'substantiation' "$output" || fail "S7 — the message does not mention 'substantiation'"

# And the count moves along: substantiating one row makes it twenty.
# Substantiate one row. Not with `sed '0,/re/'`: that address range is a GNU
# extension that BSD sed on macOS does not know, and the substitution then
# silently does not take.
awk '
  !done && sub(/requires substantiation during PRD\/architecture/, "substantiated: this project processes personal data") { done = 1 }
  { print }
' "$project/WORKFLOW-ADOPTION.md" > "$SANDBOX/table.tmp"
mv "$SANDBOX/table.tmp" "$project/WORKFLOW-ADOPTION.md"

after="$SANDBOX/after.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$after" 2>/dev/null
grep -q '20 row(s)' "$after" || {
  fail "S7 — the count does not move along after substantiating one row"
  grep -i 'row(s)' "$after" >&2
}

# Once all rows are substantiated, the message disappears — otherwise it becomes noise.
sed -i.bak 's/at adoption — requires substantiation during PRD\/architecture/substantiated/g' \
  "$project/WORKFLOW-ADOPTION.md"
rm -f "$project/WORKFLOW-ADOPTION.md.bak"

empty="$SANDBOX/empty.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$empty" 2>/dev/null
if grep -qi 'waiting on substantiation' "$empty"; then
  fail "S7 — the message remains while everything is substantiated"
fi

# And the count only looks at table rows. A loose note outside the table that
# happens to contain the same words is not a pending substantiation —
# answered() anchors on the ID column for the same reason.
printf '\nLoose note: this requires substantiation at some point.\n' \
  >> "$project/WORKFLOW-ADOPTION.md"

with_note="$SANDBOX/with-note.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$with_note" 2>/dev/null
if grep -qi 'waiting on substantiation' "$with_note"; then
  fail "S7 — a note outside the table counts as a pending substantiation"
  grep -i 'row(s)' "$with_note" >&2
fi

test_done
