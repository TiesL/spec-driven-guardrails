#!/usr/bin/env bash
# S290 — Codex public Interface and evidence contract.
# Covers: F45, F48, F51
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/codex-455.py" "$TEST_REPO_ROOT" 290
