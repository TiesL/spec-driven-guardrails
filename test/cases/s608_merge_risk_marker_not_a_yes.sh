#!/usr/bin/env bash
# S608 — A report's marker alone is never a yes; the position line is binding (#646)
# Covers: F71
#
# Red stub (Developer, #646): the behavior is specified in TEST-SCENARIOS.md S608
# and A58 and is not implemented yet; the green commit replaces this body with
# the scenario's Given/When/Then.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
fail "S608 - not implemented (#646): A report's marker alone is never a yes; the position line is binding"
test_done
