#!/usr/bin/env bash
# S506 — Reviewer head evidence excludes incidental and historical hex (#618 AC1)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/dispatch-residuals-618.py" sha "$TEST_REPO_ROOT" "$SANDBOX" || fail "S506 — dispatch residual assertions failed"
test_done
