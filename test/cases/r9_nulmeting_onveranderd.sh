#!/usr/bin/env bash
# R9 — The four existing projects get no question asked again.
# Dekt: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

nulmeting="$TEST_REPO_ROOT/test/fixtures/nulmeting"

for project in $NULMETING_PROJECTEN; do
  fixture="$nulmeting/$project"
  gouden="$fixture/verwacht-openstaand.txt"

  if [ ! -f "$gouden" ]; then
    fail "R9 — golden set is missing: $project"
    continue
  fi

  # When: pending-changes.sh runs against the frozen fixture.
  huidig="$SANDBOX/$project-huidig.txt"
  openstaande_ids "$fixture" > "$huidig"

  # Then: count and identity exactly equal to the baseline. If it deviates,
  # assert_ids_gelijk names the difference per ID - a silent change in the
  # question set is never acceptable, not even as "cleanup".
  assert_ids_gelijk "R9 — $project" "$gouden" "$huidig"
done

test_klaar
