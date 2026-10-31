#!/usr/bin/env bash
# S475 — reviewer contract rejects targeted mutations.
# Covers: F41
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/role-contract-mutations-611.py" "$TEST_REPO_ROOT" reviewer \
  || fail "S475 — reviewer mutation coverage"
test_done
