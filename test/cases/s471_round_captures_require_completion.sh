#!/usr/bin/env bash
# S471 — failed captures warn without a verdict; successful empty captures are quiet.
# Covers: F42, F28
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 "$TEST_REPO_ROOT/test/fixtures/round-capture-failures.py" "$TEST_REPO_ROOT" "$SANDBOX" \
  || fail "S471 — capture completion must be distinguished from legitimate emptiness"
test_done
