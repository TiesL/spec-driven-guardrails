#!/usr/bin/env bash
# S58 — A git hook that cannot form a judgment lets it through.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# A copy of the repo where regels.sh is removed — the source script is
# missing, exactly the case from S58.
repo="$(sandbox_copy_repo)"
rm -f "$repo/hooks/regels.sh"

project="$(vers_project kapotte-bron)"
mkdir -p "$project/.git/hooks"
ln -s "$repo/hooks/pre-commit" "$project/.git/hooks/pre-commit"
ln -s "$repo/hooks/pre-push" "$project/.git/hooks/pre-push"

# Given/When: a commit on main, while regels.sh is missing.
git -C "$project" commit -q --allow-empty -m "eerste commit"
uitvoer="$(cd "$project" && git commit -q --allow-empty -m "tweede commit op main" 2>&1)"
status=$?

# Then: a loud warning, and the command just proceeds.
[ "$status" -eq 0 ] || fail "S58 — the commit was blocked while regels.sh is missing (must fail open)"
assert_contains "S58 — a warning appears" "warning" "$uitvoer"

test_klaar
