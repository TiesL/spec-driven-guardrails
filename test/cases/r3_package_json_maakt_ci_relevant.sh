#!/usr/bin/env bash
# R3 — package.json makes ci-conventie relevant.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project leeg)"
adopteer "$project"

zonder="$SANDBOX/zonder.txt"
openstaande_ids "$project" > "$zonder"

if grep -qx 'ci-conventie' "$zonder"; then
  fail "R3 — ci-conventie was already open without package.json"
fi

# Given: the same project, now with a package.json.
echo '{"name":"t"}' > "$project/package.json"

# When/Then: ci-conventie additionally appears as open.
met="$SANDBOX/met.txt"
openstaande_ids "$project" > "$met"

grep -qx 'ci-conventie' "$met" || fail "R3 — ci-conventie did not appear after adding package.json"

# And nothing else changes: the difference is exactly the four IDs attached to
# `heeft-package-json`. `ci-conventie` is about what the CI does,
# `ci-op-pr-en-main` about when it runs, `ci-schakel-3-hard-slot` and
# `ci-detecteert-main-buiten-pr` about extra steps it also carries out;
# answerable independently, but dependent on the same predicate.
verschil="$(comm -13 "$zonder" "$met" | tr '\n' ' ')"
[ "$verschil" = "ci-conventie ci-detecteert-main-buiten-pr ci-op-pr-en-main ci-schakel-3-hard-slot " ] \
  || fail "R3 — difference is '$verschil', expected 'ci-conventie ci-detecteert-main-buiten-pr ci-op-pr-en-main ci-schakel-3-hard-slot'"

test_klaar
