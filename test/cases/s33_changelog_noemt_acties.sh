#!/usr/bin/env bash
# S33 — De CHANGELOG noemt de vereiste handmatige acties.
# Dekt: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

changelog="$TEST_REPO_ROOT/CHANGELOG.md"

[ -f "$changelog" ] || { fail "S33 — CHANGELOG.md ontbreekt"; test_klaar; }

inhoud="$(cat "$changelog")"

assert_contains "S33 — noemt adopt.sh per project" "adopt.sh" "$inhoud"
assert_contains "S33 — noemt adopt.sh --user per machine" "adopt.sh --user" "$inhoud"

test_klaar
