#!/usr/bin/env bash
# S622 — A crash or a duplicate wake neither drops nor double-merges (#646)
# Covers: F73
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S622
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S622 - not implemented (#646): A crash or a duplicate wake neither drops nor double-merges"
test_done
