#!/usr/bin/env bash
# S90 — CHANGES.md.snapshot stays in step with CHANGES.md.
# Covers: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

baseline="$TEST_REPO_ROOT/test/fixtures/baseline"
snapshot="$baseline/CHANGES.md.snapshot"

if [ ! -f "$snapshot" ]; then
  fail "S90 — test/fixtures/baseline/CHANGES.md.snapshot is missing"
  test_done
fi

# The smoke detector: CHANGES.md.snapshot must today be exactly equal to
# CHANGES.md. #160 found this had silently drifted (562 lines) since #127 —
# nothing caught it because nothing compared the two. LEESMIJ.md's own
# documented procedure says any change to CHANGES.md, even pure prose,
# should refresh this snapshot in the same PR, purely to preserve identity
# so a later diff reads as a signal instead of noise. This check is what
# makes that procedure enforced instead of a convention nobody checks.
if ! diff_output="$(diff "$TEST_REPO_ROOT/CHANGES.md" "$snapshot" 2>&1)"; then
  fail "S90 — CHANGES.md.snapshot is out of step with CHANGES.md (refresh it: cp CHANGES.md test/fixtures/baseline/CHANGES.md.snapshot):"
  printf '%s\n' "$diff_output" >&2
fi

test_done
