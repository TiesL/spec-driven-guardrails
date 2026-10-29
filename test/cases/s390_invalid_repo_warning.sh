#!/usr/bin/env bash
# S390 — Invalid or repeated repository selections are unknown (#593 AC9).
# Covers: F8
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
PYTHONDONTWRITEBYTECODE=1 python3 "$TEST_REPO_ROOT/test/fixtures/merge-repo-593.py" "$TEST_REPO_ROOT" 390
