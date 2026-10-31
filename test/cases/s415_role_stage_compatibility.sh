#!/usr/bin/env bash
# S415 — Stage-only prompts retain merge-base behavior (#599 AC3, AC7)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" compatibility "$TEST_REPO_ROOT" "$SANDBOX" || fail "S415 — AC3, AC7 public seam assertions failed (see above)"
test_done
