#!/usr/bin/env bash
# S409 — Machine-local bundle is ignored and its manifest digest is owned.
# Covers: F47
# Issue #594 AC10. Public seams and isolated fixture: test/fixtures/codex-594.py.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 409
