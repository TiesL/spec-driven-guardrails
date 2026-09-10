#!/usr/bin/env bash
# S33 — The CHANGELOG mentions the required manual actions.
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

changelog="$TEST_REPO_ROOT/CHANGELOG.md"

[ -f "$changelog" ] || { fail "S33 — CHANGELOG.md is missing"; test_klaar; }

inhoud="$(cat "$changelog")"

# Two separate assertions, not one on "adopt.sh" plus one on "adopt.sh --user":
# "adopt.sh" alone always matches as soon as the --user form appears anywhere,
# so the first assertion could never fail on its own. A line without "--user"
# that still mentions "adopt.sh" proves that the per-project instruction is
# stated separately from the per-machine instruction.
zonder_user="$(printf '%s\n' "$inhoud" | grep -v -- '--user')"
assert_contains "S33 — mentions adopt.sh per project (separate from --user)" "adopt.sh" "$zonder_user"
assert_contains "S33 — mentions adopt.sh --user per machine" "adopt.sh --user" "$inhoud"

test_klaar
