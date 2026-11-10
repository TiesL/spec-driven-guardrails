#!/usr/bin/env bash
# S628 — Every merge-decision input is itself reserved (#646; A58 addendum 3 decision 1, addenda 4 and 5; AC3)
# Covers: F72
#
# A test-local closure resolver over the committed tree (no network, no
# model) starts from the guard's entry points and the s605-s627 cases (code
# edges and data reads), then from `check` and the ci.yml `run:` steps (code
# edges only), follows the edge rules of A58 addenda 4 and 5 (copies of the
# repository resolve to repository files), and asks the verifier's
# `--phase class` bundle adapter, one 1-line bundle per file, whether each
# closure file, each wiring member and each data read by a merge-decision
# file is referred with `reserved-path` (or is a named SUBJECT_READS entry).
# Rows (a)-(j), the control (d), the exemption and SUBJECT_READS lists and the
# ten mutation checks live in test/fixtures/merge-risk-closure-646.py; the
# control prints the closure, the wiring members, the data reads and each
# exemption with the file using it.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
TMPDIR="$SANDBOX" python3 "$TEST_REPO_ROOT/test/fixtures/merge-risk-closure-646.py" 628 \
  || fail "S628 - closure rows or mutation checks failed (FAIL lines above)"
test_done
