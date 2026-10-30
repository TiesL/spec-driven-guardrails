#!/usr/bin/env bash
# S403 — Structural status distinguishes absent, current, stale and corrupt bundles.
# Covers: F47, F51
# Issue #594 AC6, AC11. Public seams and isolated fixture: test/fixtures/codex-594.py.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 403
