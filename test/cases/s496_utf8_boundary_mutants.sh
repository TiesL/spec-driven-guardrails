#!/usr/bin/env bash
# S496 — utf8 boundary mutants (#616).
# Covers: F38
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/override-616.py" 496 || fail "S496 — #616 witness"
test_done
