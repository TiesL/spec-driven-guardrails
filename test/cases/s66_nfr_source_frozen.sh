#!/usr/bin/env bash
# S66 — The source of the question set is fully frozen, including the nfr part.
# Covers: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

baseline="$TEST_REPO_ROOT/test/fixtures/baseline"
snapshot="$baseline/nfr.snapshot"

if [ ! -d "$snapshot" ]; then
  fail "S66 — test/fixtures/baseline/nfr.snapshot is missing: the nfr part of the question set is not frozen"
  test_done
fi

count="$(find "$snapshot" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
if [ "$count" -lt 1 ]; then
  fail "S66 — nfr.snapshot does not contain a single file"
fi

# AC5: it may be a derived/copied snapshot, provided it stays valid itself —
# a corrupt freeze would let the safety net silently drain out.
# shellcheck source=../../lib/nfr.sh
. "$TEST_REPO_ROOT/lib/nfr.sh"
if ! problems="$(nfr_validate "$snapshot")"; then
  fail "S66 — nfr.snapshot is not itself valid:"
  printf '%s\n' "$problems" >&2
fi

# Every spec-*-ID from every golden set must be traceable to a frozen nfr
# file — otherwise that ID would depend only on the current, non-frozen form
# of nfr/, exactly the gap that W28 closes. A missing golden set is, here just
# as in R9, an error and not a reason to silently skip that fixture.
for project in $BASELINE_PROJECTS; do
  golden="$baseline/$project/verwacht-openstaand.txt"
  if [ ! -f "$golden" ]; then
    fail "S66 — golden set missing: $project"
    continue
  fi
  while IFS= read -r id; do
    case "$id" in
      spec-*)
        if [ ! -f "$snapshot/$id.md" ]; then
          fail "S66 — $id (golden set of $project) has no frozen source in nfr.snapshot"
        fi ;;
    esac
  done < "$golden"
done

# The smoke detector: nfr.snapshot/ must today be exactly equal to nfr/.
# That is meant to go off one day — namely as soon as nfr/ legitimately
# changes without the freeze following along — and that is exactly the moment
# LEESMIJ.md's refresh procedure applies. Without this check, a deleted,
# retired, or substantively changed register file would let the snapshot
# silently go stale: S66 above only sees IDs that occur in a golden set, not
# every register file on its own.
if ! diff_output="$(diff -r "$TEST_REPO_ROOT/nfr" "$snapshot" 2>&1)"; then
  fail "S66 — nfr.snapshot is out of step with nfr/ (see LEESMIJ.md to refresh):"
  printf '%s\n' "$diff_output" >&2
fi

test_done
