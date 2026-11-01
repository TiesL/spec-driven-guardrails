#!/usr/bin/env bash
# S495 — physical symlink parent (#616).
# Covers: F38
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/override-616.py" 495 || fail "S495 — #616 witness"
test_done
