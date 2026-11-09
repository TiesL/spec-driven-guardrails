#!/usr/bin/env bash
# S625 — Live narrow start: shipped disabled, no shadow phase, coverage upper bound reported (#646)
# Covers: F74
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S625
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S625 - not implemented (#646): Live narrow start: shipped disabled, no shadow phase, coverage upper bound reported"
test_done
