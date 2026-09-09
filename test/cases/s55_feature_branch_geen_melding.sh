#!/usr/bin/env bash
# S55 — On a feature branch, the session start reports nothing.
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

# A loose grep on "main" would false-positive on, for example,
# "spec-maintainability" — the exact message text is what counts.
if printf '%s\n' "$uitvoer" | grep -q 'You are on main\|git checkout -b'; then
  fail "S55 — a message about main still appeared on a feature branch"
fi

# And: exit 0 and nothing on stderr, per S43.
status=0
"$TEST_REPO_ROOT/pending-changes.sh" "$project" >/dev/null 2>/dev/null || status=$?
[ "$status" -eq 0 ] || fail "S55 — pending-changes.sh gave exit $status instead of 0"
[ -z "$fout" ] || fail "S55 — something appeared on stderr: $fout"

test_klaar
