#!/usr/bin/env bash
# S25 — De user-level skill staat op userniveau.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project s25)"
CLAUDE_WORKFLOW_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1

doel="$HOME/.claude/skills/adopt-workflow/SKILL.md"
[ -f "$doel" ] || fail "S25 — $doel bestaat niet na 'adopt.sh --user'"

[ ! -e "$project/.claude/skills" ] \
  || fail "S25 — het (niet-geadopteerde) project heeft een .claude/skills, terwijl adopt-workflow userbreed hoort te landen"

# Tweede run: idempotent, geen kapotte link.
CLAUDE_WORKFLOW_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1
[ -f "$doel" ] || fail "S25 — een tweede '--user'-run liet de skill niet bestaan"

test_klaar "S25"
