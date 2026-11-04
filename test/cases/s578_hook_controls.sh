#!/usr/bin/env bash
# S578 — The real CLI exposes actionable epic findings; #651, A52–A53.
# Covers: F64, F66
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=test/fixtures/epic-651-helpers.sh
. "$TEST_REPO_ROOT/test/fixtures/epic-651-helpers.sh"
epic_651_run 578
