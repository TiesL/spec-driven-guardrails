#!/usr/bin/env bash
# S134 — A managed path already tracked before adoption gets untracked,
# so the .gitignore entry adopt.sh writes actually takes effect (#243 AC2).
# Covers: F9
#
# Found via #238 (portfolio-mgt-agents): CLAUDE.md was committed as an
# absolute, machine-local symlink before adoption ran; .gitignore's
# managed block was already ineffective because the file predated it, and
# adopt.sh never ran git rm --cached on already-tracked managed paths.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project pretracked-claude-md)"
printf 'not yet a symlink\n' > "$project/CLAUDE.md"
git -C "$project" add CLAUDE.md
git -C "$project" commit -q -m "pre-adoption commit, CLAUDE.md tracked as a real file"

# Sanity check on the fixture itself before adopting.
tracked_before="$(git -C "$project" ls-files CLAUDE.md)"
[ -n "$tracked_before" ] || fail "S134 — fixture setup: CLAUDE.md was not tracked before adopt"

adopt "$project"

tracked_after="$(git -C "$project" ls-files CLAUDE.md)"
[ -z "$tracked_after" ] || fail "S134 — CLAUDE.md is still tracked after adopt.sh ran"

# The working-tree file itself is kept (now the real symlink adopt.sh
# creates) — untracking must never mean deleting.
[ -L "$project/CLAUDE.md" ] || fail "S134 — CLAUDE.md was not left as a symlink after untracking"

assert_contains "S134 — .gitignore lists CLAUDE.md" "CLAUDE.md" "$(cat "$project/.gitignore")"

# And: a project where CLAUDE.md was never tracked (the common case)
# doesn't error or print anything odd — untrack_managed_paths is a no-op.
project2="$(fresh_project never-tracked)"
git -C "$project2" commit -q --allow-empty -m start
adopt "$project2"
[ -L "$project2/CLAUDE.md" ] || fail "S134 — normal-case CLAUDE.md symlink creation was affected"

test_done
