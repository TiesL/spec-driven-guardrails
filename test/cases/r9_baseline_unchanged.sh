#!/usr/bin/env bash
# R9 — The four existing projects get no question asked again.
# Covers: F2

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

baseline="$TEST_REPO_ROOT/test/fixtures/baseline"

for project in $BASELINE_PROJECTS; do
  fixture="$baseline/$project"
  golden="$fixture/verwacht-openstaand.txt"

  if [ ! -f "$golden" ]; then
    fail "R9 — golden set is missing: $project"
    continue
  fi

  # When: pending-changes.sh runs against the frozen fixture.
  current="$SANDBOX/$project-current.txt"
  pending_ids "$fixture" > "$current"

  # Then: count and identity exactly equal to the baseline. If it deviates,
  # assert_ids_equal names the difference per ID - a silent change in the
  # question set is never acceptable, not even as "cleanup".
  assert_ids_equal "R9 — $project" "$golden" "$current"
done

test_done
