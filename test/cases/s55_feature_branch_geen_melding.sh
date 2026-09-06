#!/usr/bin/env bash
# S55 — Op een feature-branch meldt de sessiestart niets.
# Dekt: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project op-feature)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/iets

uitvoer="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>/dev/null)"
fout="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1 >/dev/null)"

# Losse grep op "main" zou vals-positief slaan op bijvoorbeeld
# "spec-maintainability" — de exacte meldingstekst telt.
if printf '%s\n' "$uitvoer" | grep -q 'Je zit op main\|git checkout -b'; then
  fail "S55 — op een feature-branch verscheen toch een melding over main"
fi

# And: exit 0 en niets op stderr, conform S43.
status=0
"$TEST_REPO_ROOT/pending-changes.sh" "$project" >/dev/null 2>/dev/null || status=$?
[ "$status" -eq 0 ] || fail "S55 — pending-changes.sh gaf exit $status in plaats van 0"
[ -z "$fout" ] || fail "S55 — er kwam iets op stderr: $fout"

test_klaar
