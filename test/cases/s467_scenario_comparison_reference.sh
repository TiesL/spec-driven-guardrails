#!/usr/bin/env bash
# S467 — fixture reconstruction compares whole committed bytes without repository writes
# Covers: F60
# A49 has a text-only production seam: this reference is not production validation.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/fixtures/scenario-artifact-reference-cases.py" || fail "S467 — comparison reference does not meet A49"
# This scenario must also fail until the loaded contract actually requires the
# reference's operation. Green fixture behavior alone cannot bless missing policy.
python3 -I "$TEST_REPO_ROOT/test/fixtures/oracle-contract-pins.py" 466 || fail "S467 — comparison contract absent from loaded text"
test_done
