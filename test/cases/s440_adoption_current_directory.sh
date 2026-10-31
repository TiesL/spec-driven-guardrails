#!/usr/bin/env bash
# S440 — Current-directory adoption works under Bash 3.2.
# Covers: F47
# Issue #594 AC5, AC6. Public adoption seam; disposable project only.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 440
