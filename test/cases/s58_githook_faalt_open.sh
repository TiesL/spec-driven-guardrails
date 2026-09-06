#!/usr/bin/env bash
# S58 — Een git-hook die zijn oordeel niet kan vellen, laat door.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Een kopie van de repo waarin regels.sh weg is — het bronscript ontbreekt,
# precies het geval uit S58.
repo="$(sandbox_copy_repo)"
rm -f "$repo/hooks/regels.sh"

project="$(vers_project kapotte-bron)"
mkdir -p "$project/.git/hooks"
ln -s "$repo/hooks/pre-commit" "$project/.git/hooks/pre-commit"
ln -s "$repo/hooks/pre-push" "$project/.git/hooks/pre-push"

# Given/When: een commit op main, terwijl regels.sh ontbreekt.
git -C "$project" commit -q --allow-empty -m "eerste commit"
uitvoer="$(cd "$project" && git commit -q --allow-empty -m "tweede commit op main" 2>&1)"
status=$?

# Then: luide waarschuwing, en het commando gaat gewoon door.
[ "$status" -eq 0 ] || fail "S58 — de commit werd geblokkeerd terwijl regels.sh ontbreekt (moet faal-open zijn)"
assert_contains "S58 — er verschijnt een waarschuwing" "waarschuwing" "$uitvoer"

test_klaar
