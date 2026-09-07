#!/usr/bin/env bash
# S77 — CLAUDE_WORKFLOW_DIR (de naam van vóór W32/#56) werkt nog als
# SPEC_DRIVEN_GUARDRAILS_DIR ontbreekt, met een zichtbare waarschuwing.
# Dekt: W32 AC5

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
project="$(vers_project doelproject)"

# Given: alleen de oude naam is gezet, de nieuwe niet.
unset SPEC_DRIVEN_GUARDRAILS_DIR 2>/dev/null || true
uitvoer="$(CLAUDE_WORKFLOW_DIR="$repo" "$repo/adopt.sh" "$project" 2>&1)"
status=$?

# Then: adopt.sh werkt gewoon (geen regressie voor wie nog niet is overgestapt).
[ "$status" -eq 0 ] || fail "S77 — adopt.sh faalde met alleen CLAUDE_WORKFLOW_DIR gezet: $uitvoer"
[ -L "$project/CLAUDE.md" ] || fail "S77 — CLAUDE.md-symlink ontbreekt na adoptie via de oude naam"

# And: de waarschuwing over de verouderde naam is zichtbaar.
printf '%s' "$uitvoer" | grep -qi 'CLAUDE_WORKFLOW_DIR.*verouderd' \
  || fail "S77 — geen waarschuwing over de verouderde omgevingsvariabele. Uitvoer: $uitvoer"

# --- Regressie: staat de nieuwe naam er ook, dan wint die en blijft de
# waarschuwing weg — anders zou iedereen die al gemigreerd is de melding
# blijven zien.
project2="$(vers_project tweedeproject)"
uitvoer2="$(CLAUDE_WORKFLOW_DIR="/pad/dat/niet/bestaat" SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$project2" 2>&1)"
status2=$?
[ "$status2" -eq 0 ] || fail "S77 — adopt.sh faalde terwijl SPEC_DRIVEN_GUARDRAILS_DIR wél klopte: $uitvoer2"
printf '%s' "$uitvoer2" | grep -qi 'verouderd' \
  && fail "S77 — waarschuwing verscheen terwijl SPEC_DRIVEN_GUARDRAILS_DIR gezet was (had voorrang moeten krijgen)"

test_klaar
