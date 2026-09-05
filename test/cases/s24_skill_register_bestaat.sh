#!/usr/bin/env bash
# S24 — Elke skill in het register bestaat en is vindbaar.
# Dekt: F10
#
# Alle negen skills uit PRD.md F10, niet alleen de vijf die in de Wegwijzer
# landen: `tdd-seams` en `diagnose-bug` krijgen hun inhoud pas in W14/W15, maar
# horen nu al als SKILL.md te bestaan (stub), anders liegt het register.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skills="pre-merge-review deploy-guards check-convention adoption-registry write-spec refactoring-triggers tdd-seams diagnose-bug adopt-workflow"

for naam in $skills; do
  pad="$TEST_REPO_ROOT/skills/$naam/SKILL.md"
  if [ ! -f "$pad" ]; then
    fail "S24 — $pad ontbreekt"
    continue
  fi
  grep -q '^name:' "$pad" \
    || fail "S24 — $naam/SKILL.md heeft geen 'name:' in de frontmatter"
  grep -q '^description:' "$pad" \
    || fail "S24 — $naam/SKILL.md heeft geen 'description:' in de frontmatter"
done

test_klaar "S24"
