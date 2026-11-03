#!/usr/bin/env bash
# S527 — A26 has a dated current model-only round-trip amendment.
# Covers: F39, F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" amendment "$TEST_REPO_ROOT" \
  || fail "S527 — A26 has a dated current model-only round-trip amendment (including mutation controls)"
test_done
