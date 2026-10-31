#!/usr/bin/env bash
# S478 — pushback contract rejects targeted mutations.
# Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/role-contract-mutations-611.py" "$TEST_REPO_ROOT" pushback \
  || fail "S478 — pushback mutation coverage"
test_done
