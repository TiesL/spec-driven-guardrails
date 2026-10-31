#!/usr/bin/env bash
# S469 — a valid Test waiver exempts QA provenance with narrow add-only scope
# Covers: F59, F60
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/skip-test-qa-exemption-pins.py" || fail "S469 — skip=Test exemption missing from loaded contracts"
test_done
