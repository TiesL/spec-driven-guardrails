#!/usr/bin/env bash
# S626 — The skill lives in its own file and survives compaction (#646)
# Covers: F74
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S626
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S626 - not implemented (#646): The skill lives in its own file and survives compaction"
test_done
