#!/usr/bin/env bash
# R3 — package.json maakt ci-conventie relevant.
# Dekt: F3

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
  fail "R3 — ci-conventie stond al open zonder package.json"
fi

# Given: hetzelfde project, nu met een package.json.
echo '{"name":"t"}' > "$project/package.json"

# When/Then: ci-conventie verschijnt aanvullend als openstaand.
met="$SANDBOX/met.txt"
openstaande_ids "$project" > "$met"

grep -qx 'ci-conventie' "$met" || fail "R3 — ci-conventie verscheen niet na toevoegen van package.json"

# En verder verandert er niets: het verschil is precies die ene ID.
verschil="$(comm -13 "$zonder" "$met" | tr '\n' ' ')"
[ "$verschil" = "ci-conventie " ] || fail "R3 — verschil is '$verschil', alleen 'ci-conventie' verwacht"

test_klaar
