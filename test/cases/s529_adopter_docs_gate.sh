#!/usr/bin/env bash
# S529 — Model record gate header names the guard within 79 columns.
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" gate "$TEST_REPO_ROOT" \
  || fail "S529 — Model record gate header names the guard within 79 columns (including mutation controls)"
test_done
