#!/usr/bin/env bash
# S468 — published command handles bytes, CRLF transport and changed bases
# Covers: F60
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/scenario-comparison-command-cases.py" || fail "S468 — published comparison command failed its byte oracle"
test_done
