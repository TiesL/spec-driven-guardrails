#!/usr/bin/env bash
# S434 — Versions 1 through 3 remain readable and upgrade explicitly.
# Covers: F47, F51
# Issue #594 AC5, AC6. Public adoption seam; fixture-only fault injection.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 434
