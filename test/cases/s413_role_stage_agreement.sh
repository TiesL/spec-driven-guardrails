#!/usr/bin/env bash
# S413 — The #595 prompt is denied before dispatch (#599 AC5, AC8)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" agreement "$TEST_REPO_ROOT" "$SANDBOX" || fail "S413 — AC5, AC8 public seam assertions failed (see above)"
test_done
