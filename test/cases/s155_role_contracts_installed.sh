#!/usr/bin/env bash
# S155 — adopt.sh installs role-contracts as a skill, with no wip/ file needed.
# Covers: F37
#
# Issue #369, AC1. Seam: adopt.sh's own output in a fresh project (the
# .claude/skills/ symlink it leaves behind), never adopt.sh's internals.
# The clone is a sandbox copy with its wip/ directory deleted, so a skill
# that only works while wip/ exists can't pass by accident.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a guardrails clone without any wip/ content, and a fresh project.
clone="$(sandbox_copy_repo clone)"
rm -rf "$clone/wip"
project="$(fresh_project adopter)"

# When: the project adopts the workflow from that clone.
if ! SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >"$SANDBOX/adopt.log" 2>&1; then
  fail "S155 — adopt.sh failed on a clone without wip/:"
  cat "$SANDBOX/adopt.log" >&2
fi

# Then: .claude/skills/role-contracts is a symlink into the clone's skills/.
link="$project/.claude/skills/role-contracts"
if [ ! -L "$link" ]; then
  fail "S155 — .claude/skills/role-contracts is not a symlink after adoption"
  test_done
fi
target="$(readlink "$link")"
case "$target" in
  "$clone/skills/role-contracts" | "$clone/skills/role-contracts/") ;;
  *) fail "S155 — role-contracts points to '$target', not to the clone's skills/role-contracts" ;;
esac

# And: the skill it resolves to is readable and declares itself by name, so
# Claude Code can load it.
skill="$link/SKILL.md"
if [ ! -r "$skill" ]; then
  fail "S155 — the installed role-contracts skill has no readable SKILL.md"
elif ! grep -q '^name: role-contracts$' "$skill"; then
  fail "S155 — the installed SKILL.md does not declare 'name: role-contracts' in its frontmatter"
fi

test_done
