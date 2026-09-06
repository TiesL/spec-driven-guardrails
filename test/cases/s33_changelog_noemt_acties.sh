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

# Twee losse asserties, niet één op "adopt.sh" plus één op "adopt.sh --user":
# "adopt.sh" alleen matcht altijd mee zodra de --user-vorm ergens voorkomt,
# en dan kan de eerste assertie nooit apart falen. Een regel zonder "--user"
# die toch "adopt.sh" noemt, bewijst dat de per-project-instructie er los van
# de per-machine-instructie staat.
zonder_user="$(printf '%s\n' "$inhoud" | grep -v -- '--user')"
assert_contains "S33 — noemt adopt.sh per project (los van --user)" "adopt.sh" "$zonder_user"
assert_contains "S33 — noemt adopt.sh --user per machine" "adopt.sh --user" "$inhoud"

test_klaar
