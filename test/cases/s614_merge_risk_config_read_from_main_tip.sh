#!/usr/bin/env bash
# S614 — The configuration is read from the main tip; a candidate cannot widen itself (#646)
# Covers: F72
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S614
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S614 - not implemented (#646): The configuration is read from the main tip; a candidate cannot widen itself"
test_done
