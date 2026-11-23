#!/usr/bin/env bash
# S705 — A routed parent refuses a Claude child (#707; AC6)
# Covers: F75
#
# Seam: the inherited ANTHROPIC_BASE_URL matrix through the wrapper's process
# Interface. First-party means exactly https://api.anthropic.com; unset is
# the only other value that passes.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S705 — route-child.sh is missing or not executable"; test_done; }

refused=(http://127.0.0.1:8787/w/claude http://localhost:9 http://api.anthropic.com
  https://api.anthropic.com.evil.example https://api.anthropic.com/v1 https://api.anthropic.com/ '')
for value in "${refused[@]}"; do
  label="S705/refused/[$value]"
  rc_env_reset
  rc_env_set "ANTHROPIC_BASE_URL=$value"
  rc_run claude -- "$RC/bin/claude" -p x
  [ "$rc_status" = 4 ] || fail "$label — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started"
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
  for need in "already routed" ANTHROPIC_BASE_URL settings shell; do
    grep -qi -- "$need" <<<"$rc_err" || fail "$label — the message lacks '$need': $rc_err"
  done
  # The Codex adapter does not look at the variable.
  rc_run codex -- "$RC/bin/codex" exec x
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "$label/codex — the Codex adapter refused: exit $rc_status, $rc_err"
  # With the answer not yes the run is unchanged.
  rc_answer no
  rc_direct "$RC/bin/claude" -p x
  rc_run claude -- "$RC/bin/claude" -p x
  [ "$rc_started" = 1 ] && [ -z "$(rc_env_diff)" ] || fail "$label/not-yes — not run unchanged: exit $rc_status, $rc_err"
  rc_answer yes
done

# Controls: unset and exactly first-party route the child.
for value in UNSET https://api.anthropic.com; do
  rc_env_reset
  [ "$value" = UNSET ] || rc_env_set "ANTHROPIC_BASE_URL=$value"
  rc_direct "$RC/bin/claude" -p x
  rc_run claude -- "$RC/bin/claude" -p x
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S705/control/$value — refused: exit $rc_status, $rc_err"
  [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "S705/control/$value — not routed as in S701: $(rc_env_diff)"
done

test_done
