#!/usr/bin/env bash
# S414 — Role and stage disagreements refuse before marker validation (#599 AC1, AC2, AC7)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" pairs "$TEST_REPO_ROOT" "$SANDBOX" || fail "S414 — AC1, AC2, AC7 public seam assertions failed (see above)"
test_done
