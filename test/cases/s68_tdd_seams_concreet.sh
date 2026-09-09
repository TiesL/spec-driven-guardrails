#!/usr/bin/env bash
# S68 — `tdd-seams` benoemt de discipline concreet, niet aansporend.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/tdd-seams/SKILL.md"

[ -f "$skill" ] || { fail "S68 — skills/tdd-seams/SKILL.md ontbreekt"; test_klaar; }

inhoud="$(cat "$skill")"

assert_contains "S68 — noemt 'seam'" "seam" "$inhoud"
assert_contains "S68 — noemt red" "red" "$inhoud"
assert_contains "S68 — noemt green" "green" "$inhoud"
assert_contains "S68 — anti-patroon: implementation-coupled" "mplementation-coupled" "$inhoud"
assert_contains "S68 — anti-patroon: tautological" "autological" "$inhoud"
assert_contains "S68 — anti-patroon: horizontal slicing" "orizontal slicing" "$inhoud"
assert_contains "S68 — tegenover vertical slices" "ertical slices" "$inhoud"

test_klaar
