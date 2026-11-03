#!/usr/bin/env bash
# S476 — reclassification contract rejects targeted mutations.
# Covers: F42
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/role-contract-mutations-611.py" "$TEST_REPO_ROOT" reclassification \
  || fail "S476 — reclassification mutation coverage"
test_done
