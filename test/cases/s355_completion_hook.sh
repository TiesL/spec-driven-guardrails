#!/usr/bin/env bash
# S355-S360 — completion behavior through the executable hook Interface.
# Covers: F56
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/completion-hook.py" "$TEST_REPO_ROOT" "$SANDBOX" || fail "completion hook behavior"
test_done
