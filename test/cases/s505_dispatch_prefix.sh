#!/usr/bin/env bash
# S505 — Exact role prefixes reject QA-lead (#618 AC1)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/dispatch-residuals-618.py" prefix "$TEST_REPO_ROOT" "$SANDBOX" || fail "S505 — dispatch residual assertions failed"
test_done
