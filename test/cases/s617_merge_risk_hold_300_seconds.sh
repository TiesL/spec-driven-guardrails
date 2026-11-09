#!/usr/bin/env bash
# S617 — The hold: 299 seconds waits, 300 may proceed (#646)
# Covers: F73
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S617
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S617 - not implemented (#646): The hold: 299 seconds waits, 300 may proceed"
test_done
