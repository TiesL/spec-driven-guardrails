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
assert_contains "S68 — noemt rood" "rood" "$inhoud"
assert_contains "S68 — noemt groen" "groen" "$inhoud"
assert_contains "S68 — anti-patroon: implementatie-gekoppeld" "mplementatie-gekoppeld" "$inhoud"
assert_contains "S68 — anti-patroon: tautologisch" "autologisch" "$inhoud"
assert_contains "S68 — anti-patroon: horizontaal slicen" "orizontaal slicen" "$inhoud"
assert_contains "S68 — tegenover verticale slices" "erticale slices" "$inhoud"

test_klaar
