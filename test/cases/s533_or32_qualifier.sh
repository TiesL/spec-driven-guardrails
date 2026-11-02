#!/usr/bin/env bash
# S533 — OR32 keeps the "Resolve absolute path once" qualifier (#620)
# Covers: F38
#
# Seam: skills/role-contracts/ORCHESTRATOR.md read as text. The pin hash is
# guarded by S311, S317, S322 and S333; this test guards the phrase itself.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

ORCH="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"

# or32_ok <file> : exactly one OR32 line, containing the phrase.
or32_ok() {
  [ "$(grep -c '^- OR32 ' "$1")" = 1 ] || return 1
  grep -qF 'Resolve absolute path once' <<<"$(grep '^- OR32 ' "$1")"
}

or32_ok "$ORCH" || fail "S533 — OR32 lacks 'Resolve absolute path once'"

# Mutant: the phrase deleted in a scratch copy.
sed '/^- OR32 /s/Resolve absolute path once: //' "$ORCH" >"$SANDBOX/m.md"
cmp -s "$ORCH" "$SANDBOX/m.md" && fail "S533/mutant — the deletion changed nothing"
or32_ok "$SANDBOX/m.md" && fail "S533/mutant — OR32 without the phrase passed"
test_done
