#!/usr/bin/env bash
# S1 — `check` faalt op een syntaxfout in een script.
# Dekt: F1

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: een script in dit repo met een bash-syntaxfout.
printf '\nif [ 1 -eq 1 ]; then\n  echo kapot\n' >> "$repo/pending-changes.sh"

# When: ./check draait (zonder de testsuite, anders roept de suite zichzelf aan).
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, met het betreffende bestand in de melding.
if [ "$status" -eq 0 ]; then
  fail "S1 — check slaagde terwijl er een syntaxfout in pending-changes.sh staat"
fi
assert_contains "S1" "pending-changes.sh" "$uitvoer"

test_klaar
