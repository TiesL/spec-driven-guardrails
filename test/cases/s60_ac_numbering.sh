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

sjabloon="$TEST_REPO_ROOT/templates/ISSUE_TEMPLATE/work-item.md"

# Given: the template for a work item.
[ -f "$sjabloon" ] || { fail "S60 — work-item.md is missing"; test_klaar; }

# Then: the criteria are numbered AC<n>.
grep -qE '^#+ +AC[0-9]+' "$sjabloon" \
  || fail "S60 — no AC<n>-numbered acceptance criterion in work-item.md"

# And: no more own S<n> numbering. A heading like `### S1:` is the numbering;
# `S2b` in running text is a reference and may remain. The distinction is in
# the heading, not in the letter's occurrence.
eigen_nummering="$(grep -nE '^#+ +S[0-9]+' "$sjabloon" || true)"
[ -z "$eigen_nummering" ] \
  || fail "S60 — work-item.md still numbers itself with S<n>: $eigen_nummering"

# And: the template carries the coverage field, at line start.
grep -q '^\*\*Covers:\*\*' "$sjabloon" \
  || fail "S60 — work-item.md has no '**Covers:**' at line start"

# And: **Covers:** sits between Epic and Blocked by. That is not a matter of
# taste: every existing issue in this repo writes that order, and a template
# that models a different order produces two notations, one of which would
# accidentally become the norm later on.
volgorde="$(grep -nE '^\*\*(Epic|Covers|Blocked by|Blocks):\*\*' "$sjabloon" | sed 's/^[0-9]*://; s/:\*\*.*/:**/' | tr '\n' ' ')"
verwacht="**Epic:** **Covers:** **Blocked by:** **Blocks:** "
[ "$volgorde" = "$verwacht" ] \
  || fail "S60 — field order is '$volgorde', expected '$verwacht'"

# And: the loose lines that Covers: replaces are gone. If they remain, there are
# two ways to write the same thing and nobody can guess which one counts.
for oud in "PRD-sectie" "TEST-SCENARIOS.md-scenario"; do
  grep -q "^$oud" "$sjabloon" \
    && fail "S60 — '$oud' is still there alongside **Covers:**"
done

test_klaar "S60"
