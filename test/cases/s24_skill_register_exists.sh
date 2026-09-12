#!/usr/bin/env bash
# S24 — Every skill in the register exists and is findable.
# Covers: F10
#
# All nine skills from PRD.md F10, not just the five that land in the routing
# table: `tdd-seams` and `diagnose-bug` only get their content in W14/W15, but
# should already exist as SKILL.md (stub) now, otherwise the register lies.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skills="pre-merge-review deploy-guards check-convention adoption-registry write-spec refactoring-triggers tdd-seams diagnose-bug adopt-workflow"

for naam in $skills; do
  pad="$TEST_REPO_ROOT/skills/$naam/SKILL.md"
  if [ ! -f "$pad" ]; then
    fail "S24 — $pad is missing"
    continue
  fi
  grep -q '^name:' "$pad" \
    || fail "S24 — $naam/SKILL.md has no 'name:' in the frontmatter"
  grep -q '^description:' "$pad" \
    || fail "S24 — $naam/SKILL.md has no 'description:' in the frontmatter"
done

test_done "S24"
