#!/usr/bin/env bash
# S294 — Codex public Interface and evidence contract.
# Covers: F50, F51, F53
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/codex-455.py" "$TEST_REPO_ROOT" 294
