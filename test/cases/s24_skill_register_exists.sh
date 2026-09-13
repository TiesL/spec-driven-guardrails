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

for name in $skills; do
  path="$TEST_REPO_ROOT/skills/$name/SKILL.md"
  if [ ! -f "$path" ]; then
    fail "S24 — $path is missing"
    continue
  fi
  grep -q '^name:' "$path" \
    || fail "S24 — $name/SKILL.md has no 'name:' in the frontmatter"
  grep -q '^description:' "$path" \
    || fail "S24 — $name/SKILL.md has no 'description:' in the frontmatter"
done

test_done "S24"
