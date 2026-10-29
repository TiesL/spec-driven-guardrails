#!/usr/bin/env bash
# S386 — Origin transports, case and terminal suffix normalize consistently (#593 AC5).
# Covers: F8
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
PYTHONDONTWRITEBYTECODE=1 python3 "$TEST_REPO_ROOT/test/fixtures/merge-repo-593.py" "$TEST_REPO_ROOT" 386
