#!/usr/bin/env bash
# R4 — A "deploy" script makes deploy-guards relevant.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project leeg)"
adopt "$project"
echo '{"name":"t"}' > "$project/package.json"

zonder="$SANDBOX/zonder.txt"
pending_ids "$project" > "$zonder"

if grep -qx 'deploy-guards' "$zonder"; then
  fail "R4 — deploy-guards was already open without a deploy script"
fi

# Given: package.json with a "deploy" script.
echo '{"name":"t","scripts":{"deploy":"node deploy.mjs"}}' > "$project/package.json"

# When/Then: deploy-guards appears as open.
met="$SANDBOX/met.txt"
pending_ids "$project" > "$met"

grep -qx 'deploy-guards' "$met" || fail "R4 — deploy-guards did not appear after adding the deploy script"

verschil="$(comm -13 "$zonder" "$met" | tr '\n' ' ')"
[ "$verschil" = "deploy-guards " ] || fail "R4 — difference is '$verschil', expected only 'deploy-guards'"

test_done
