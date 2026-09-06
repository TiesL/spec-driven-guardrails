#!/usr/bin/env bash
# R9 — De vier bestaande projecten krijgen geen enkele vraag opnieuw.
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
    fail "R9 — gouden set ontbreekt: $project"
    continue
  fi

  # When: pending-changes.sh draait tegen de ingevroren fixture.
  huidig="$SANDBOX/$project-huidig.txt"
  openstaande_ids "$fixture" > "$huidig"

  # Then: aantal én identiteit exact gelijk aan de nulmeting. Wijkt het af, dan
  # noemt assert_ids_gelijk het verschil per ID - een stille wijziging in de
  # vraagset is nooit acceptabel, ook niet als "opschoning".
  assert_ids_gelijk "R9 — $project" "$gouden" "$huidig"
done

test_klaar
