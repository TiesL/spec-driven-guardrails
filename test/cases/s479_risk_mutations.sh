#!/usr/bin/env bash
# S479 — risk contract rejects targeted mutations.
# Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/role-contract-mutations-611.py" "$TEST_REPO_ROOT" risk \
  || fail "S479 — risk mutation coverage"
test_done
