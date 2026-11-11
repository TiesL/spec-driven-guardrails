#!/usr/bin/env bash
# S628 — Historical A58 oracle retired by A60 (#646)
# Covers: F71, F72
# Retirement only; no five-vote/class/closure safety or authority claim.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
section="$(awk '/^### S628 /{on=1; next} on && /^### /{exit} on{print}' "$TEST_REPO_ROOT/TEST-SCENARIOS.md")"
# Read exactly the scenario through the next heading, without modifying it.
grep -qF 'Amended by A60: historical/superseded' <<<"$section" \
  || fail "S628 - retirement note absent"
test_done
