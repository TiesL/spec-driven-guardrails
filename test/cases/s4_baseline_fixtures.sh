#!/usr/bin/env bash
# S4 — Baseline fixture captures `a2t-emails` as found.
# Covers: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"

# The fourfold comparison of golden sets is in R9
# (r9_baseline_unchanged.sh). This scenario is specifically about whether
# a2t-emails is captured as found, without repair.

# a2t-emails is the special case: no WORKFLOW-ADOPTIE.md, so everything is
# open. Capture as found - do not repair first, otherwise the fixture
# captures the repair instead of the state.
a2t="$nulmeting/a2t-emails"

if [ -e "$a2t/WORKFLOW-ADOPTIE.md" ]; then
  fail "S4 — the a2t-emails fixture has a WORKFLOW-ADOPTIE.md; it should not be there"
fi

# Non-circular check that nothing has been answered in advance: ci-conventie is
# indeed answered in tennis-admin. If it is open here, the fixture is unrepaired.
# No `if [ -f ... ]` guard: if the golden set is missing, that is a fault and
# not a reason to silently check nothing.
if [ ! -f "$a2t/verwacht-openstaand.txt" ]; then
  fail "S4 — golden set of a2t-emails is missing"
  test_done
fi

if ! grep -qx 'ci-conventie' "$a2t/verwacht-openstaand.txt"; then
  fail "S4 — ci-conventie is missing from the a2t baseline; appears to have been answered in advance"
fi
count="$(grep -c . "$a2t/verwacht-openstaand.txt")"
if [ "$count" -lt 20 ]; then
  fail "S4 — a2t baseline only counts $count IDs; 'everything open' was expected"
fi

test_done
