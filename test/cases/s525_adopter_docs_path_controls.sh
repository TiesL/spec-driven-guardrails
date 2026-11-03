#!/usr/bin/env bash
# S525 — Installed invocation resolver rejects dangling paths.
# Covers: F37
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" path-controls "$TEST_REPO_ROOT" \
  || fail "S525 — Installed invocation resolver rejects dangling paths (including mutation controls)"
test_done
