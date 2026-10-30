#!/usr/bin/env bash
# S440 — #507 codex status failures.
# Covers: F58
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-507.py" "$TEST_REPO_ROOT" 440
