#!/usr/bin/env bash
# S606 — Votes expire when the head changes, including update-branch (#646)
# Covers: F70
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S606
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S606 - not implemented (#646): Votes expire when the head changes, including update-branch"
test_done
