#!/usr/bin/env bash
# S36 — An ID in the explanation does not count as an answer.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project met-toelichting)"
adopteer "$project"

# test-integratie has `Standaard: vraag` and is therefore never seeded: it is
# still open after a fresh adoption. That's the control value.
voor="$SANDBOX/voor.txt"
openstaande_ids "$project" > "$voor"
grep -qx 'test-integratie' "$voor" || {
  fail "S36 — test-integratie was not open after fresh adoption; the setup is broken"
  test_klaar
}

# Given: the ID appears in the free-text explanation of another row.
printf '| proces-prd | ja | 2026-01-01 | nog geen test-integratie afgesproken |\n' \
  >> "$project/WORKFLOW-ADOPTIE.md"

# When/Then: the change is still open - only the ID column counts.
na="$SANDBOX/na.txt"
openstaande_ids "$project" > "$na"

if ! grep -qx 'test-integratie' "$na"; then
  fail "S36 — test-integratie disappeared because of a mention in the explanation"
fi

test_klaar
