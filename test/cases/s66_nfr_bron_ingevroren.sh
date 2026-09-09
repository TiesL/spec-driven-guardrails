#!/usr/bin/env bash
# S66 — The source of the question set is fully frozen, including the nfr part.
# Dekt: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"
snapshot="$nulmeting/nfr.momentopname"

if [ ! -d "$snapshot" ]; then
  fail "S66 — test/fixtures/nulmeting/nfr.momentopname is missing: the nfr part of the question set is not frozen"
  test_klaar
fi

aantal="$(find "$snapshot" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
if [ "$aantal" -lt 1 ]; then
  fail "S66 — nfr.momentopname does not contain a single file"
fi

# AC5: it may be a derived/copied snapshot, provided it stays valid itself —
# a corrupt freeze would let the safety net silently drain out.
# shellcheck source=../../lib/nfr.sh
. "$TEST_REPO_ROOT/lib/nfr.sh"
if ! problemen="$(nfr_valideer "$snapshot")"; then
  fail "S66 — nfr.momentopname is not itself valid:"
  printf '%s\n' "$problemen" >&2
fi

# Every spec-*-ID from every golden set must be traceable to a frozen nfr
# file — otherwise that ID would depend only on the current, non-frozen form
# of nfr/, exactly the gap that W28 closes. A missing golden set is, here just
# as in R9, an error and not a reason to silently skip that fixture.
for project in $NULMETING_PROJECTEN; do
  gouden="$nulmeting/$project/verwacht-openstaand.txt"
  if [ ! -f "$gouden" ]; then
    fail "S66 — golden set missing: $project"
    continue
  fi
  while IFS= read -r id; do
    case "$id" in
      spec-*)
        if [ ! -f "$snapshot/$id.md" ]; then
          fail "S66 — $id (golden set of $project) has no frozen source in nfr.momentopname"
        fi ;;
    esac
  done < "$gouden"
done

# The smoke detector: nfr.momentopname/ must today be exactly equal to nfr/.
# That is meant to go off one day — namely as soon as nfr/ legitimately
# changes without the freeze following along — and that is exactly the moment
# LEESMIJ.md's refresh procedure applies. Without this check, a deleted,
# retired, or substantively changed register file would let the snapshot
# silently go stale: S66 above only sees IDs that occur in a golden set, not
# every register file on its own.
if ! verschil="$(diff -r "$TEST_REPO_ROOT/nfr" "$snapshot" 2>&1)"; then
  fail "S66 — nfr.momentopname is out of step with nfr/ (see LEESMIJ.md to refresh):"
  printf '%s\n' "$verschil" >&2
fi

test_klaar
