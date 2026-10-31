#!/usr/bin/env bash
# S410 — The pre-live baseline documents the bundle, assumptions and refresh limits.
# Covers: F51, F57
# Issue #594 AC11, AC12. Public seams and isolated fixture: test/fixtures/codex-594.py.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 410
