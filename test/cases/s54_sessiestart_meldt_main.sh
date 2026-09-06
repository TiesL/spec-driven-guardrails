#!/usr/bin/env bash
# S54 — Sessiestart meldt dat `main` is uitgecheckt.
# Dekt: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project op-main)"
git -C "$project" commit -q --allow-empty -m start

uitvoer="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>/dev/null)"

assert_contains "S54 — de melding noemt main" "main" "$uitvoer"
assert_contains "S54 — de melding stelt git checkout -b voor" "git checkout -b" "$uitvoer"

test_klaar
