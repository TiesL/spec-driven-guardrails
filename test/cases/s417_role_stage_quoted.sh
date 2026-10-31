#!/usr/bin/env bash
# S417 — Every emit line agrees with its prefix, including quoted commands by current default (#599 AC8)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" quoted "$TEST_REPO_ROOT" "$SANDBOX" || fail "S417 — AC8 public seam assertions failed (see above)"
test_done
