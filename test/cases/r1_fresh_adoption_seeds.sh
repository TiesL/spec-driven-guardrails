#!/usr/bin/env bash
# R1 — A fresh adoption seeds exactly the same rows.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: an empty git project with no package.json.
project="$(fresh_project empty)"

# When: adopt.sh is run.
adopt "$project"

table="$project/WORKFLOW-ADOPTION.md"
if [ ! -f "$table" ]; then
  fail "R1 — adopt.sh did not create WORKFLOW-ADOPTION.md"
  test_done
fi

# Then: exactly 21 rows, all carrying "requires substantiation".
rows="$(grep -c '^| [a-z]' "$table")"
[ "$rows" -eq 21 ] || fail "R1 — $rows rows seeded, 21 expected"

substantiation="$(grep -c 'requires substantiation' "$table")"
[ "$substantiation" -eq 21 ] || fail "R1 — $substantiation rows with 'requires substantiation', 21 expected"

# And: the retired legacy entry is not in there.
if grep -q 'prd-testscenarios-issue-templates' "$table"; then
  fail "R1 — retired entry prd-testscenarios-issue-templates was seeded"
fi

test_done
