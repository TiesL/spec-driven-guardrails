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
project="$(vers_project doelproject)"
adopteer "$project"

rijen="$(grep -c 'requires substantiation' "$project/WORKFLOW-ADOPTION.md")"
[ "$rijen" -eq 21 ] || fail "S7 — $rijen rows with 'requires substantiation', 21 expected"

# When: pending-changes.sh runs.
uitvoer="$SANDBOX/uitvoer.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$uitvoer" 2>/dev/null

# Then: a message appears with the count.
grep -q '21 row(s)' "$uitvoer" || {
  fail "S7 — no message with the count of pending substantiations"
  cat "$uitvoer" >&2
}
grep -qi 'substantiation' "$uitvoer" || fail "S7 — the message does not mention 'substantiation'"

# And the count moves along: substantiating one row makes it twenty.
# Substantiate one row. Not with `sed '0,/re/'`: that address range is a GNU
# extension that BSD sed on macOS does not know, and the substitution then
# silently does not take.
awk '
  !gedaan && sub(/requires substantiation tijdens PRD\/architectuur/, "onderbouwd: dit project verwerkt persoonsgegevens") { gedaan = 1 }
  { print }
' "$project/WORKFLOW-ADOPTION.md" > "$SANDBOX/tabel.tmp"
mv "$SANDBOX/tabel.tmp" "$project/WORKFLOW-ADOPTION.md"

na="$SANDBOX/na.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$na" 2>/dev/null
grep -q '20 row(s)' "$na" || {
  fail "S7 — the count does not move along after substantiating one row"
  grep -i 'row(s)' "$na" >&2
}

# Once all rows are substantiated, the message disappears — otherwise it becomes noise.
sed -i.bak 's/bij adoptie — requires substantiation tijdens PRD\/architectuur/onderbouwd/g' \
  "$project/WORKFLOW-ADOPTION.md"
rm -f "$project/WORKFLOW-ADOPTION.md.bak"

leeg="$SANDBOX/leeg.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$leeg" 2>/dev/null
if grep -qi 'waiting on substantiation' "$leeg"; then
  fail "S7 — the message remains while everything is substantiated"
fi

# And the count only looks at table rows. A loose note outside the table that
# happens to contain the same words is not a pending substantiation —
# beantwoord() anchors on the ID column for the same reason.
printf '\nLosse notitie: dit requires substantiation bij gelegenheid.\n' \
  >> "$project/WORKFLOW-ADOPTION.md"

met_notitie="$SANDBOX/met-notitie.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$met_notitie" 2>/dev/null
if grep -qi 'waiting on substantiation' "$met_notitie"; then
  fail "S7 — a note outside the table counts as a pending substantiation"
  grep -i 'row(s)' "$met_notitie" >&2
fi

test_klaar
