#!/usr/bin/env bash
# S78 — A single 'adopt.sh' run fully repoints a project with relocated symlinks
# (e.g. after the W32/#56 rename) to the new location.
# Covers: W32 AC4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project adopted from an "old" checkout location.
old="$(sandbox_copy_repo oude-checkout)"
project="$(fresh_project target-project)"
SPEC_DRIVEN_GUARDRAILS_DIR="$old" "$old/adopt.sh" "$project" >/dev/null 2>&1

[ "$(readlink "$project/CLAUDE.md")" = "$old/WORKFLOW.md" ] \
  || fail "S78 — setup: CLAUDE.md does not point to the old location"
[ "$(readlink "$project/.claude/settings.json")" = "$old/settings/session-hooks.json" ] \
  || fail "S78 — setup: settings.json does not point to the old location"

# When: the checkout "relocates" (simulates a repo rename: new directory,
# old one is gone) and adopt.sh runs again, now with the new location.
new="$SANDBOX/nieuwe-checkout"
mv "$old" "$new"
SPEC_DRIVEN_GUARDRAILS_DIR="$new" "$new/adopt.sh" "$project" >/dev/null 2>&1

# Then: both symlinks now point to the new location, in a single action.
[ "$(readlink "$project/CLAUDE.md")" = "$new/WORKFLOW.md" ] \
  || fail "S78 — CLAUDE.md does not point to the new location after the migration"
[ "$(readlink "$project/.claude/settings.json")" = "$new/settings/session-hooks.json" ] \
  || fail "S78 — settings.json does not point to the new location after the migration"

# And: a third run is a no-op — no error, no change.
after_first="$(readlink "$project/CLAUDE.md")"
SPEC_DRIVEN_GUARDRAILS_DIR="$new" "$new/adopt.sh" "$project" >/dev/null 2>&1 \
  || fail "S78 — a repeated run after migration failed"
[ "$(readlink "$project/CLAUDE.md")" = "$after_first" ] \
  || fail "S78 — a repeated run after migration changed the symlink again"

test_done
