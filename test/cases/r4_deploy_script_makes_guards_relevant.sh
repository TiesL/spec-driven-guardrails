#!/usr/bin/env bash
# R4 — A "deploy" script makes deploy-guards relevant.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project empty)"
adopt "$project"
echo '{"name":"t"}' > "$project/package.json"

without="$SANDBOX/without.txt"
pending_ids "$project" > "$without"

if grep -qx 'deploy-guards' "$without"; then
  fail "R4 — deploy-guards was already open without a deploy script"
fi

# Given: package.json with a "deploy" script.
echo '{"name":"t","scripts":{"deploy":"node deploy.mjs"}}' > "$project/package.json"

# When/Then: deploy-guards appears as open.
with="$SANDBOX/with.txt"
pending_ids "$project" > "$with"

grep -qx 'deploy-guards' "$with" || fail "R4 — deploy-guards did not appear after adding the deploy script"

difference="$(comm -13 "$without" "$with" | tr '\n' ' ')"
[ "$difference" = "deploy-guards " ] || fail "R4 — difference is '$difference', expected only 'deploy-guards'"

test_done
