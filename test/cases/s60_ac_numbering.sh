#!/usr/bin/env bash
# S60 — Acceptance criteria in the template are named AC<n>.
# Covers: F13
#
# As long as an issue names its own criteria `S1`, every grep for scenario
# references also hits the issue itself. Link 2 (scenario -> issue) is then
# not verifiable: every issue appears to reference every scenario.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

template="$TEST_REPO_ROOT/templates/ISSUE_TEMPLATE/work-item.md"

# Given: the template for a work item.
[ -f "$template" ] || { fail "S60 — work-item.md is missing"; test_done; }

# Then: the criteria are numbered AC<n>.
grep -qE '^#+ +AC[0-9]+' "$template" \
  || fail "S60 — no AC<n>-numbered acceptance criterion in work-item.md"

# And: no more own S<n> numbering. A heading like `### S1:` is the numbering;
# `S2b` in running text is a reference and may remain. The distinction is in
# the heading, not in the letter's occurrence.
own_numbering="$(grep -nE '^#+ +S[0-9]+' "$template" || true)"
[ -z "$own_numbering" ] \
  || fail "S60 — work-item.md still numbers itself with S<n>: $own_numbering"

# And: the template carries the coverage field, at line start.
grep -q '^\*\*Covers:\*\*' "$template" \
  || fail "S60 — work-item.md has no '**Covers:**' at line start"

# And: **Covers:** sits between Epic and Blocked by. That is not a matter of
# taste: every existing issue in this repo writes that order, and a template
# that models a different order produces two notations, one of which would
# accidentally become the norm later on.
order="$(grep -nE '^\*\*(Epic|Covers|Blocked by|Blocks):\*\*' "$template" | sed 's/^[0-9]*://; s/:\*\*.*/:**/' | tr '\n' ' ')"
expected="**Epic:** **Covers:** **Blocked by:** **Blocks:** "
[ "$order" = "$expected" ] \
  || fail "S60 — field order is '$order', expected '$expected'"

# And: the loose lines that Covers: replaces are gone. If they remain, there are
# two ways to write the same thing and nobody can guess which one counts.
for old in "PRD-sectie" "TEST-SCENARIOS.md-scenario"; do
  grep -q "^$old" "$template" \
    && fail "S60 — '$old' is still there alongside **Covers:**"
done

test_done "S60"
