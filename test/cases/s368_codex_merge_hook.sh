#!/usr/bin/env bash
# S368 — opt-in Codex merge hook public Interface (A47).
# Covers: F8, F45, F47, F48, F51, F52, F53
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/codex-544.py" "$TEST_REPO_ROOT" 368
