#!/usr/bin/env bash
# R1 — A fresh adoption seeds exactly the same rows.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: an empty git project with no package.json.
project="$(vers_project leeg)"

# When: adopt.sh is run.
adopteer "$project"

tabel="$project/WORKFLOW-ADOPTIE.md"
if [ ! -f "$tabel" ]; then
  fail "R1 — adopt.sh did not create WORKFLOW-ADOPTIE.md"
  test_klaar
fi

# Then: exactly 21 rows, all carrying "vereist onderbouwing".
rijen="$(grep -c '^| [a-z]' "$tabel")"
[ "$rijen" -eq 21 ] || fail "R1 — $rijen rows seeded, 21 expected"

onderbouwing="$(grep -c 'vereist onderbouwing' "$tabel")"
[ "$onderbouwing" -eq 21 ] || fail "R1 — $onderbouwing rows with 'vereist onderbouwing', 21 expected"

# And: the retired legacy entry is not in there.
if grep -q 'prd-testscenarios-issue-templates' "$tabel"; then
  fail "R1 — retired entry prd-testscenarios-issue-templates was seeded"
fi

test_klaar
