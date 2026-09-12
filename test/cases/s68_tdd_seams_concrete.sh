#!/usr/bin/env bash
# S68 — `tdd-seams` states the discipline concretely, not as exhortation.
# Covers: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/tdd-seams/SKILL.md"

[ -f "$skill" ] || { fail "S68 — skills/tdd-seams/SKILL.md is missing"; test_done; }

content="$(cat "$skill")"

assert_contains "S68 — mentions 'seam'" "seam" "$content"
assert_contains "S68 — mentions red-before-green" "Red-before-green" "$content"
assert_contains "S68 — anti-pattern: implementation-coupled" "mplementation-coupled" "$content"
assert_contains "S68 — anti-pattern: tautological" "autological" "$content"
assert_contains "S68 — anti-pattern: horizontal slicing" "orizontal slicing" "$content"
assert_contains "S68 — versus vertical slices" "ertical slices" "$content"

test_done
