#!/usr/bin/env bash
# S82 — Een verse WORKFLOW-ADOPTIE.md noemt de juiste repo-naam.
# Dekt: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een leeg git-project zonder package.json.
project="$(vers_project leeg)"

# When: adopt.sh wordt gedraaid.
adopteer "$project"

tabel="$project/WORKFLOW-ADOPTIE.md"
if [ ! -f "$tabel" ]; then
  fail "S82 — adopt.sh maakte geen WORKFLOW-ADOPTIE.md aan"
  test_klaar
fi

# Then: de header verwijst naar de huidige naam, niet naar de naam van vóór
# de W32-hernoeming (#56).
if grep -q "claude-workflow" "$tabel"; then
  fail "S82 — WORKFLOW-ADOPTIE.md verwijst nog naar de oude naam claude-workflow"
fi
grep -q "spec-driven-guardrails" "$tabel" \
  || fail "S82 — WORKFLOW-ADOPTIE.md noemt spec-driven-guardrails niet"

test_klaar
