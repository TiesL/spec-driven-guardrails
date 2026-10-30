#!/usr/bin/env bash
# S418 — Hook, emitter library and OR5 role maps cannot drift (#599 AC9)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" drift "$TEST_REPO_ROOT" "$SANDBOX" || fail "S418 — AC9 public seam assertions failed (see above)"
test_done
