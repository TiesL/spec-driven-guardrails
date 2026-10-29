#!/usr/bin/env bash
# S408 — Relative source dependencies must stay inside the declared closure.
# Covers: F8, F47
# Issue #594 AC9. Public seams and isolated fixture: test/fixtures/codex-594.py.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 408
