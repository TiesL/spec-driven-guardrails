#!/usr/bin/env bash
# R3 — package.json makes ci-convention relevant.
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

if grep -qx 'ci-convention' "$without"; then
  fail "R3 — ci-convention was already open without package.json"
fi

# Given: the same project, now with a package.json.
echo '{"name":"t"}' > "$project/package.json"

# When/Then: ci-convention additionally appears as open.
with="$SANDBOX/with.txt"
pending_ids "$project" > "$with"

grep -qx 'ci-convention' "$with" || fail "R3 — ci-convention did not appear after adding package.json"

# And nothing else changes: the difference is exactly the four IDs attached to
# `has-package-json`. `ci-convention` is about what the CI does,
# `ci-on-pr-and-main` about when it runs, `ci-link-3-hard-block` and
# `ci-detects-main-outside-pr` about extra steps it also carries out;
# answerable independently, but dependent on the same predicate.
difference="$(comm -13 "$without" "$with" | tr '\n' ' ')"
[ "$difference" = "ci-convention ci-detects-main-outside-pr ci-link-3-hard-block ci-on-pr-and-main " ] \
  || fail "R3 — difference is '$difference', expected 'ci-convention ci-detects-main-outside-pr ci-link-3-hard-block ci-on-pr-and-main'"

test_done
