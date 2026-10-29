#!/usr/bin/env bash
# S405 — Codex adoption continues to write no configuration or trust.
# Covers: F47, F57
# Issue #594 AC7. Public seams and isolated fixture: test/fixtures/codex-594.py.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 405
