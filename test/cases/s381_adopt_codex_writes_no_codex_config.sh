#!/usr/bin/env bash
# S381 — adopt.sh with Codex options writes no Codex config under HOME and grants no trust.
# Covers: F57
#
# Issue #590, AC8, AC12. Regression guard (green on today's tree): the
# existing S365-S369 snapshot a user-owned ~/.codex; this one also covers
# the no-.codex-at-all home and the trust keys. Falsifiers: a ~/.codex
# created, a hooks.state or trust_level entry anywhere adopt.sh wrote.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

proj="$(fresh_project proj)"
for args in "--runtime codex" "--runtime codex --hooks"; do
  # shellcheck disable=SC2086
  out="$(SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" $args "$proj" 2>&1)" \
    || fail "S381 — adopt.sh $args failed: $out"
  [ ! -e "$HOME/.codex" ] || fail "S381 — adopt.sh $args created ~/.codex"
done
[ -f "$proj/.codex/hooks.json" ] || fail "S381 — --hooks did not install the project hook file"
trust_hits="$(grep -rIl -e 'hooks\.state' -e 'trust_level' "$proj/.codex" "$proj/.guardrails" 2>/dev/null || true)"
if [ -n "$trust_hits" ]; then
  fail "S381 — adopt.sh wrote a trust entry"
fi

test_done
