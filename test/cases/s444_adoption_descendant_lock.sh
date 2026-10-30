#!/usr/bin/env bash
# S444 — Descendant inherited descriptor cannot authorize overlapping adoption.
# Covers: F47, F51
# Issue #594 AC5, AC6; A47. Public adoption seam; disposable project only.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 444
