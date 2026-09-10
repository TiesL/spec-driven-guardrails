#!/usr/bin/env bash
# S38 — A field without a preceding heading yields no entry.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a malformed source — a field before the first heading.
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

# shellcheck disable=SC2329  # called indirectly, via itereer_entries
noteer() { printf '%s\n' "$1" >> "$gezien"; }

# When: itereer_entries reads that source.
itereer_entries "$bron" noteer

# Then: only the entry after the heading was seen; the loose field yielded
# nothing. wc -l, not grep -c: a callback with an empty ID writes an empty
# line, and that must be counted too - that's exactly the case this scenario
# is looking for.
aantal="$(wc -l < "$gezien" | tr -d ' ')"
[ "$aantal" -eq 1 ] || fail "S38 — $aantal callbacks, expected 1 (field without heading is counted)"
grep -qx 'echte-entry' "$gezien" || fail "S38 — the entry after the heading was not processed"

# And: there was no call with an empty ID.
if grep -qx '' "$gezien"; then
  fail "S38 — callback called with an empty ID"
fi

# And: the same holds via adopt.sh itself. Before W4, the guard was only in
# pending-changes.sh; with such a malformed source, adopt.sh produced a row
# with an empty ID. This check runs through the real script instead of
# through the library, because geseede_ids() filters on '^| [a-z]' and would
# never see an empty-ID row.
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
  fail "S38 — adopt.sh wrote a row with an empty ID"
  grep -nE '^\| *\|' "$tabel" >&2
fi

test_klaar
