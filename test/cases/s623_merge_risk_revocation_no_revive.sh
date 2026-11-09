#!/usr/bin/env bash
# S623 — Revocation stops everything and does not revive (#646)
# Covers: F73, F74
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S623
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S623 - not implemented (#646): Revocation stops everything and does not revive"
test_done
