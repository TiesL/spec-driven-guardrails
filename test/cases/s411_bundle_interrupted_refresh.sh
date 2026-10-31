#!/usr/bin/env bash
# S411 — Interrupted bundle refresh preserves policy and permits explicit recovery.
# Covers: F47, F51
# Issue #594 AC5, AC6. Public seams and isolated fixture: test/fixtures/codex-594.py.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 411
