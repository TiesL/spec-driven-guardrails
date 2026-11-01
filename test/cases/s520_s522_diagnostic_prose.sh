#!/usr/bin/env bash
# S520-S522 — Unfolded diagnostics and scoped historical prose (#624). Covers: F43
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/s520-diagnostic-prose.py" "$TEST_REPO_ROOT" || fail "S520-S522 diagnostics/prose controls"
test_done
