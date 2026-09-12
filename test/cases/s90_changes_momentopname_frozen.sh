#!/usr/bin/env bash
# S90 — CHANGES.md.momentopname stays in step with CHANGES.md.
# Covers: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"
snapshot="$nulmeting/CHANGES.md.momentopname"

if [ ! -f "$snapshot" ]; then
  fail "S90 — test/fixtures/nulmeting/CHANGES.md.momentopname is missing"
  test_done
fi

# The smoke detector: CHANGES.md.momentopname must today be exactly equal to
# CHANGES.md. #160 found this had silently drifted (562 lines) since #127 —
# nothing caught it because nothing compared the two. LEESMIJ.md's own
# documented procedure says any change to CHANGES.md, even pure prose,
# should refresh this snapshot in the same PR, purely to preserve identity
# so a later diff reads as a signal instead of noise. This check is what
# makes that procedure enforced instead of a convention nobody checks.
if ! verschil="$(diff "$TEST_REPO_ROOT/CHANGES.md" "$snapshot" 2>&1)"; then
  fail "S90 — CHANGES.md.momentopname is out of step with CHANGES.md (refresh it: cp CHANGES.md test/fixtures/nulmeting/CHANGES.md.momentopname):"
  printf '%s\n' "$verschil" >&2
fi

test_done
