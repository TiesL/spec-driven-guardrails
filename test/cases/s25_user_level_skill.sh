#!/usr/bin/env bash
# S25 — The user-level skill lives at the user level.
# Covers: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project s25)"
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1

target="$HOME/.claude/skills/adopt-workflow/SKILL.md"
[ -f "$target" ] || fail "S25 — $target does not exist after 'adopt.sh --user'"

# F10: adopt-workflow is the only user-level skill. Not just "exists", also
# "nothing else is there" - otherwise this isn't a real check.
count="$(find "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
[ "$count" -eq 1 ] \
  || fail "S25 — \$HOME/.claude/skills contains $count item(s), expected 1 (only adopt-workflow)"

[ ! -e "$project/.claude" ] \
  || fail "S25 — the (unadopted) project got a .claude directory, while adopt-workflow should land user-wide"

# Second run: idempotent, no broken link.
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1
[ -f "$target" ] || fail "S25 — a second '--user' run left the skill not existing"

# --- Regression: an orphaned link stays cleanable, even once the skill itself
# has since disappeared from the source. Without this, every session in every
# project reports a load error, because the previous installation left a dead
# link behind.
bare="$(sandbox_copy_repo bare)"
rm -rf "$HOME/.claude"
SPEC_DRIVEN_GUARDRAILS_DIR="$bare" "$bare/adopt.sh" --user >/dev/null 2>&1
[ -L "$HOME/.claude/skills/adopt-workflow" ] \
  || fail "S25 — the preparatory install (bare copy) did not create a symlink"

rm -rf "$bare/skills/adopt-workflow"
SPEC_DRIVEN_GUARDRAILS_DIR="$bare" "$bare/adopt.sh" --user >/dev/null 2>&1
if [ -e "$HOME/.claude/skills/adopt-workflow" ] || [ -L "$HOME/.claude/skills/adopt-workflow" ]; then
  fail "S25 — an orphaned adopt-workflow link at the user level was not cleaned up after the source disappeared"
fi

# --- Regression: a user's own ~/.claude/skills symlink stays intact. This is
# the whole personal skill namespace on this machine, not something belonging
# to this repo - "when in doubt, discard nothing" applies here even more
# strongly than in a project.
rm -rf "$HOME/.claude"
mkdir -p "$SANDBOX/elders-skills/own-skill"
echo "# from the user themselves" > "$SANDBOX/elders-skills/own-skill/SKILL.md"
mkdir -p "$HOME/.claude"
ln -s "$SANDBOX/elders-skills" "$HOME/.claude/skills"

SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" --user >/dev/null 2>&1

[ -L "$HOME/.claude/skills" ] \
  || fail "S25 — a user's own ~/.claude/skills symlink was replaced by a real directory"
bestemming="$(readlink "$HOME/.claude/skills")"
[ "$bestemming" = "$SANDBOX/elders-skills" ] \
  || fail "S25 — the user's own ~/.claude/skills symlink no longer points to the same place"
[ -f "$SANDBOX/elders-skills/own-skill/SKILL.md" ] \
  || fail "S25 — the content behind the user's own symlink disappeared"
[ -f "$SANDBOX/elders-skills/adopt-workflow/SKILL.md" ] \
  || fail "S25 — adopt-workflow was not installed inside the user's own symlink target"

test_done "S25"
