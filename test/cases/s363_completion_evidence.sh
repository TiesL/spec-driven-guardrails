#!/usr/bin/env bash
# S363-S364 — validate the recorded live observations and explicit reset gaps.
# Covers: F56
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
# This validates recorded evidence, never reruns paid/live sessions in CI.
python3 "$TEST_REPO_ROOT/test/completion-evidence.py" "$TEST_REPO_ROOT" || fail "completion evidence"
test_done
