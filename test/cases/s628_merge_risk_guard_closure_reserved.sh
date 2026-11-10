#!/usr/bin/env bash
# S628 — Everything the reserved merge guard runs is itself reserved (#646; A58 addendum 3 decision 1, addendum 4; AC3)
# Covers: F72
#
# A test-local closure resolver over the committed tree (no network, no
# model) starts from the guard's entry points and the s605-s627 cases,
# follows the edge rules of A58 addendum 4, and asks the verifier's
# `--phase class` bundle adapter, one 1-line bundle per file, whether each
# closure file and each wiring member is referred with `reserved-path`.
# Rows (a)-(g), the control (d), the exemption list and the seven mutation
# checks live in test/fixtures/merge-risk-closure-646.py; the control prints
# the closure, the wiring members and each exemption with the file using it.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 "$TEST_REPO_ROOT/test/fixtures/merge-risk-closure-646.py" 628 \
  || fail "S628 - closure rows or mutation checks failed (FAIL lines above)"
test_done
