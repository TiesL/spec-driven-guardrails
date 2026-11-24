#!/usr/bin/env bash
# S608 — A report's marker alone is never a yes; the position line is binding (#646; A58 D5; AC2)
# Covers: F71
# Retirement only; no five-vote/class/closure safety or authority claim.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
section="$(awk '/^### S608 /{on=1; next} on && /^### /{exit} on{print}' "$TEST_REPO_ROOT/TEST-SCENARIOS.md")"
# Read exactly the scenario through the next heading, without modifying it.
grep -qFx -- '- Amended by A60: historical/superseded. The following A58 oracle is retained as history and supplies no current merge authority. Do not execute its obsolete five-vote/closure assertion as a live safety requirement. Replacement coverage: S650-S659, S615.' <<<"$section" \
  || fail "S608 - retirement note absent"
test_done
