#!/usr/bin/env bash
# S412 — Role-only dispatches pass and invalid forms stay fail-closed (#599 AC5, AC8)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" dispatch "$TEST_REPO_ROOT" "$SANDBOX" || fail "S412 — AC5, AC8 public seam assertions failed (see above)"
test_done
