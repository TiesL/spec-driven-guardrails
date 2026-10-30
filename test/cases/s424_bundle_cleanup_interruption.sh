#!/usr/bin/env bash
# S424 — Cleanup deletion and metadata clearing interruptions.
# Covers: F47, F51
# Issue #594 AC5, AC6. Public adoption seam; fixture-only fault injection.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 424
