#!/usr/bin/env bash
# R1 — Verse adoptie seedt exact dezelfde rijen.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een leeg git-project zonder package.json.
project="$(vers_project leeg)"

# When: adopt.sh wordt gedraaid.
adopteer "$project"

tabel="$project/WORKFLOW-ADOPTIE.md"
if [ ! -f "$tabel" ]; then
  fail "R1 — adopt.sh maakte geen WORKFLOW-ADOPTIE.md aan"
  test_klaar
fi

# Then: exact 20 rijen, allemaal met "vereist onderbouwing".
rijen="$(grep -c '^| [a-z]' "$tabel")"
[ "$rijen" -eq 20 ] || fail "R1 — $rijen rijen geseed, 20 verwacht"

onderbouwing="$(grep -c 'vereist onderbouwing' "$tabel")"
[ "$onderbouwing" -eq 20 ] || fail "R1 — $onderbouwing rijen met 'vereist onderbouwing', 20 verwacht"

# And: de geretireerde legacy-entry staat er niet in.
if grep -q 'prd-testscenarios-issue-templates' "$tabel"; then
  fail "R1 — geretireerde entry prd-testscenarios-issue-templates is geseed"
fi

test_klaar
