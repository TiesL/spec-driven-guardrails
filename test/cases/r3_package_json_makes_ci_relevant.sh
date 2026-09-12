#!/usr/bin/env bash
# R3 — package.json makes ci-conventie relevant.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project empty)"
adopt "$project"

without="$SANDBOX/without.txt"
pending_ids "$project" > "$without"

if grep -qx 'ci-conventie' "$without"; then
  fail "R3 — ci-conventie was already open without package.json"
fi

# Given: the same project, now with a package.json.
echo '{"name":"t"}' > "$project/package.json"

# When/Then: ci-conventie additionally appears as open.
with="$SANDBOX/with.txt"
pending_ids "$project" > "$with"

grep -qx 'ci-conventie' "$with" || fail "R3 — ci-conventie did not appear after adding package.json"

# And nothing else changes: the difference is exactly the four IDs attached to
# `heeft-package-json`. `ci-conventie` is about what the CI does,
# `ci-op-pr-en-main` about when it runs, `ci-schakel-3-hard-slot` and
# `ci-detecteert-main-buiten-pr` about extra steps it also carries out;
# answerable independently, but dependent on the same predicate.
difference="$(comm -13 "$without" "$with" | tr '\n' ' ')"
[ "$difference" = "ci-conventie ci-detecteert-main-buiten-pr ci-op-pr-en-main ci-schakel-3-hard-slot " ] \
  || fail "R3 — difference is '$difference', expected 'ci-conventie ci-detecteert-main-buiten-pr ci-op-pr-en-main ci-schakel-3-hard-slot'"

test_done
