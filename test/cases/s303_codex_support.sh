#!/usr/bin/env bash
# S303 — Codex public Interface and evidence contract.
# Covers: F52, F53
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/codex-455.py" "$TEST_REPO_ROOT" 303
