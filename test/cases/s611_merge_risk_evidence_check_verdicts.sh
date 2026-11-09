#!/usr/bin/env bash
# S611 — The read-only evidence check reports one of four verdicts with every reason (#646)
# Covers: F72
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S611
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S611 - not implemented (#646): The read-only evidence check reports one of four verdicts with every reason"
test_done
