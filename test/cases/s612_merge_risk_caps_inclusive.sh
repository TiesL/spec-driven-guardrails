#!/usr/bin/env bash
# S612 — Caps are inclusive and both counts must be positive (#646)
# Covers: F72
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S612
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S612 - not implemented (#646): Caps are inclusive and both counts must be positive"
test_done
