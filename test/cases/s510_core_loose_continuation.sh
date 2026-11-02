#!/usr/bin/env bash
# S510 — #619 core loose continuation
# Covers: F38
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/core-integrity-tests.py" loose || fail "S510 — loose regression"
test_done
