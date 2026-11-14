#!/usr/bin/env bash
# S628 — Every merge-decision input is itself reserved (#646; A58 addendum 3 decision 1, addendum 4, addendum 5; AC3)
# Covers: F72
# Retirement only; no five-vote/class/closure safety or authority claim.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
section="$(awk '/^### S628 /{on=1; next} on && /^### /{exit} on{print}' "$TEST_REPO_ROOT/TEST-SCENARIOS.md")"
# Read exactly the scenario through the next heading, without modifying it.
grep -qFx -- '- Amended by A60: historical/superseded. The following A58 oracle is retained as history and supplies no current merge authority. Do not execute its obsolete five-vote/closure assertion as a live safety requirement. Replacement coverage: S613, S662-S665 and substantive qualification S670-S674; no replacement closure proof.' <<<"$section" \
  || fail "S628 - retirement note absent"
test_done
