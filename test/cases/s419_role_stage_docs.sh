#!/usr/bin/env bash
# S419 — Instructing docs pin role commands and retain grammar ownership (#599 AC6, AC7)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" docs "$TEST_REPO_ROOT" "$SANDBOX" || fail "S419 — AC6, AC7 public seam assertions failed (see above)"
test_done
