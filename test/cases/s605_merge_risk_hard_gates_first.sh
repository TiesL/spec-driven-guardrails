#!/usr/bin/env bash
# S605 — Hard gates come first and are never votes (#646)
# Covers: F70
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S605
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S605 - not implemented (#646): Hard gates come first and are never votes"
test_done
