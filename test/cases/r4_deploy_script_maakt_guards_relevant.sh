#!/usr/bin/env bash
# R4 — Een "deploy"-script maakt deploy-guards relevant.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project leeg)"
adopteer "$project"
echo '{"name":"t"}' > "$project/package.json"

zonder="$SANDBOX/zonder.txt"
openstaande_ids "$project" > "$zonder"

if grep -qx 'deploy-guards' "$zonder"; then
  fail "R4 — deploy-guards stond al open zonder deploy-script"
fi

# Given: package.json met een "deploy"-script.
echo '{"name":"t","scripts":{"deploy":"node deploy.mjs"}}' > "$project/package.json"

# When/Then: deploy-guards verschijnt als openstaand.
met="$SANDBOX/met.txt"
openstaande_ids "$project" > "$met"

grep -qx 'deploy-guards' "$met" || fail "R4 — deploy-guards verscheen niet na toevoegen van het deploy-script"

verschil="$(comm -13 "$zonder" "$met" | tr '\n' ' ')"
[ "$verschil" = "deploy-guards " ] || fail "R4 — verschil is '$verschil', alleen 'deploy-guards' verwacht"

test_klaar
