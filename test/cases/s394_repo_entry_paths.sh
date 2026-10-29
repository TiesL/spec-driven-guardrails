#!/usr/bin/env bash
# S394 — Claude, Codex merge-only and numeric preflight preserve verdicts (#593 AC13).
# Covers: F8
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
PYTHONDONTWRITEBYTECODE=1 python3 "$TEST_REPO_ROOT/test/fixtures/merge-repo-593.py" "$TEST_REPO_ROOT" 394
