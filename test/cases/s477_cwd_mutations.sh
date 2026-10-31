#!/usr/bin/env bash
# S477 — cwd contract rejects targeted mutations.
# Covers: F42
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/role-contract-mutations-611.py" "$TEST_REPO_ROOT" cwd \
  || fail "S477 — cwd mutation coverage"
test_done
