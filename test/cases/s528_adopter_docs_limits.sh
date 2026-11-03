#!/usr/bin/env bash
# S528 — S240 names caught shapes and known limits.
# Covers: F39, F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" limits "$TEST_REPO_ROOT" \
  || fail "S528 — S240 names caught shapes and known limits (including mutation controls)"
test_done
