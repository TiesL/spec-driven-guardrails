#!/usr/bin/env bash
# S507 — Reviewer PR references accept the supported spellings (#618 AC1)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -I "$TEST_REPO_ROOT/test/fixtures/dispatch-residuals-618.py" pr "$TEST_REPO_ROOT" "$SANDBOX" || fail "S507 — dispatch residual assertions failed"
test_done
