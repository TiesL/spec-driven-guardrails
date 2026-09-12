#!/usr/bin/env bash
# S92 — `check` runs this repo's own traceability check (link 1).
# Covers: F13

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: a scenario whose Covers: field carries an invalid token — the
# exact shape of bug #147 was filed over (S85's own "F6, W42/#114", found
# only because check-traceability.sh happened to be run by hand).
printf '\n### S999 — Injected for S92\n**Covers:** F6, W42/#114\n- Given: nothing\n- When: nothing\n- Then: nothing\n' \
  >> "$repo/TEST-SCENARIOS.md"

# When: ./check runs.
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: check fails, and names the broken token — not silently green
# while schakel 1 is broken on this repo's own PRD.md/TEST-SCENARIOS.md.
if [ "$status" -eq 0 ]; then
  fail "S92 — check succeeded despite an invalid Covers: token in TEST-SCENARIOS.md"
fi
assert_contains "S92" "W42/#114" "$uitvoer"

# And: on the real, unmodified repo (no injected error), check-traceability.sh
# itself must still be part of ./check's output — proving it actually ran,
# not just that it would have caught this one artificial case.
schoon_uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$TEST_REPO_ROOT" 2>&1)"
schoon_status=$?
[ "$schoon_status" -eq 0 ] || fail "S92 — check failed on this repo's own, currently-clean PRD.md/TEST-SCENARIOS.md: $schoon_uitvoer"
assert_contains "S92 — check-traceability.sh ran" "traceability" "$schoon_uitvoer"

test_done
