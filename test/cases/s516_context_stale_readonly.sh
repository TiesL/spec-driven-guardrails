#!/usr/bin/env bash
# S516 — Cold stale-bundle context preserves trees and diagnostics.
# Covers: F47, F51
# Issue #621 AC1; public CLI seams and disposable native-exchange observer.
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 -B "$TEST_REPO_ROOT/test/fixtures/codex-594.py" "$TEST_REPO_ROOT" 516
