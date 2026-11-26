#!/usr/bin/env bash
# S722 — #706 loaded instruction obligations and deletion controls.
# Covers: F76, F38, F60, F62
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/wip-promotion-706.py" 722 || fail "S722 — #706 instruction obligations missing"
test_done
