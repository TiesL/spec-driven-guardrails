#!/usr/bin/env bash
# S38 — A field without a preceding heading yields no entry.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a malformed source — a field before the first heading.
source="$SANDBOX/CHANGES.md"
cat > "$source" <<'MD'
# Adopteerbare wijzigingen

- **Applies if:** always

## echte-entry

- **Default:** yes
- **Applies if:** always
MD

seen="$SANDBOX/seen.txt"
: > "$seen"

# shellcheck disable=SC2329  # called indirectly, via iterate_entries
noteer() { printf '%s\n' "$1" >> "$seen"; }

# When: iterate_entries reads that source.
iterate_entries "$source" noteer

# Then: only the entry after the heading was seen; the loose field yielded
# nothing. wc -l, not grep -c: a callback with an empty ID writes an empty
# line, and that must be counted too - that's exactly the case this scenario
# is looking for.
count="$(wc -l < "$seen" | tr -d ' ')"
[ "$count" -eq 1 ] || fail "S38 — $count callbacks, expected 1 (field without heading is counted)"
grep -qx 'echte-entry' "$seen" || fail "S38 — the entry after the heading was not processed"

# And: there was no call with an empty ID.
if grep -qx '' "$seen"; then
  fail "S38 — callback called with an empty ID"
fi

# And: the same holds via adopt.sh itself. Before W4, the guard was only in
# pending-changes.sh; with such a malformed source, adopt.sh produced a row
# with an empty ID. This check runs through the real script instead of
# through the library, because seeded_ids() filters on '^| [a-z]' and would
# never see an empty-ID row.
nep="$SANDBOX/nepworkflow"
mkdir -p "$nep/lib" "$nep/templates"
cp "$TEST_REPO_ROOT/lib/changes.sh" "$nep/lib/"
cp "$TEST_REPO_ROOT/adopt.sh" "$nep/"
echo "# Werkwijze" > "$nep/WORKFLOW.md"
cp "$source" "$nep/CHANGES.md"

project="$(fresh_project target-project)"
SPEC_DRIVEN_GUARDRAILS_DIR="$nep" "$nep/adopt.sh" "$project" >/dev/null 2>&1

table="$project/WORKFLOW-ADOPTION.md"
if [ -f "$table" ] && grep -qE '^\| *\|' "$table"; then
  fail "S38 — adopt.sh wrote a row with an empty ID"
  grep -nE '^\| *\|' "$table" >&2
fi

test_done
