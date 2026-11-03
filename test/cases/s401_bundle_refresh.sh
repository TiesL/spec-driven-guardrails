#!/usr/bin/env bash
# S401 — Only explicit refresh updates bundle contents and reports unchanged trust declaration.
# Covers: F47, F51
# Issue #594 AC5, AC6. Public seams and isolated fixture: test/fixtures/codex-594.py.
# #621 also checks cold standalone status over the entire temporary tree.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 401
