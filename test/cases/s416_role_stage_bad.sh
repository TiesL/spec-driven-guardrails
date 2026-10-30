#!/usr/bin/env bash
# S416 — Invalid role arguments follow the refusal discipline (#599 AC1, AC4)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" bad "$TEST_REPO_ROOT" "$SANDBOX" || fail "S416 — AC1, AC4 public seam assertions failed (see above)"
test_done
