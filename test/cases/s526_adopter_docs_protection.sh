#!/usr/bin/env bash
# S526 — Private and public protection framing agrees with README.
# Covers: F37
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" protection "$TEST_REPO_ROOT" \
  || fail "S526 — Private and public protection framing agrees with README (including mutation controls)"
test_done
