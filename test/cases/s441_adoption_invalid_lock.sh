#!/usr/bin/env bash
# S441 — Invalid environment descriptor cannot bypass writer lock.
# Covers: F47, F51
# Issue #594 AC5, AC6. Public adoption seam; disposable project only.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 441
