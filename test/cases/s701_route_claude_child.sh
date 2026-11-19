#!/usr/bin/env bash
# S701 — A routed Claude child gets exactly four additions and the parent is untouched (#707; AC2)
# Covers: F75
#
# Seam: route-child.sh run as a process (test/fixtures/route-child-helpers.sh):
# stub child, probe stub, and the environment diff against the same stub run
# directly. Answer yes, probe up, clean fixture settings.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S701 — route-child.sh is missing or not executable"; test_done; }

# Clean settings in every checked location (no env.ANTHROPIC_BASE_URL).
mkdir -p "$RC_TOP/.claude" "$RC_CWD/.claude"
echo '{"permissions": {"allow": []}}' >"$RC/cfg/settings.json"
echo '{}' >"$RC_TOP/.claude/settings.json"
echo '{"env": {"FOO": "1"}}' >"$RC_TOP/.claude/settings.local.json"
echo '{"hooks": {}}' >"$RC_CWD/.claude/settings.json"
before="$(rc_tree_hash "$RC/home" "$RC/cfg" "$RC/codexhome" "$RC/managed" "$RC_TOP")"

stub="$RC/bin/claude"
args=(-p 'a prompt with spaces' "q'uote\"d" '' -- --model x)

# --- (a) clean environment ------------------------------------------------
rc_direct "$stub" "${args[@]}"
rc_run claude -- "$stub" "${args[@]}"
[ "$rc_status" = 0 ] || fail "S701/a — exit $rc_status, expected 0 (stderr: $rc_err)"
[ "$rc_started" = 1 ] || fail "S701/a — the child was not started"
got="$(rc_env_diff)"
want="$(rc_expected_claude_diff)"
[ "$got" = "$want" ] || fail "S701/a — environment differs from a direct run by:
$got
expected exactly:
$want"
rc_args_equal_direct || fail "S701/a — the arguments were changed (no --bare, --setting-sources or --settings may be added)"
[ "$(cat "$RC/log/probe.log")" = "-s -o /dev/null --connect-timeout 2 --max-time 3 http://127.0.0.1:8787/" ] \
  || fail "S701/a — the probe was not called once with the curl arguments: '$(cat "$RC/log/probe.log")'"
[ -z "$rc_out" ] || fail "S701/a — the wrapper printed on stdout: $rc_out"

# --- (b) inherited NO_PROXY, headers and session variables ----------------
rc_env_set "NO_PROXY=corp.example"
rc_env_set "ANTHROPIC_CUSTOM_HEADERS=x-keep: 1"
rc_env_set "ANTHROPIC_API_KEY=k"
rc_env_set "CLAUDECODE=1"
rc_env_set "CLAUDE_CODE_SESSION_ID=s"
rc_direct "$stub" "${args[@]}"
rc_run claude -- "$stub" "${args[@]}"
[ "$rc_started" = 1 ] || fail "S701/b — the child was not started (exit $rc_status, stderr: $rc_err)"
got="$(rc_env_diff)"
want="$(rc_expected_claude_diff corp.example 'x-keep: 1')"
[ "$got" = "$want" ] || fail "S701/b — inherited values not appended as specified:
$got
expected exactly:
$want"
rc_args_equal_direct || fail "S701/b — the arguments were changed"
rc_env_reset

# --- exit status is the child's own ----------------------------------------
for code in 0 1 3 4 130; do
  rc_env_set "STUB_EXIT=$code"
  rc_run claude -- "$stub" -p x
  [ "$rc_status" = "$code" ] || fail "S701/exit — the child exited $code, the wrapper exited $rc_status"
  [ "$rc_started" = 1 ] || fail "S701/exit — the child was not started for STUB_EXIT=$code"
done
rc_env_reset

# --- nothing was written ------------------------------------------------------
after="$(rc_tree_hash "$RC/home" "$RC/cfg" "$RC/codexhome" "$RC/managed" "$RC_TOP")"
[ "$before" = "$after" ] || fail "S701 — a fixture settings file, HOME, CODEX_HOME or the project changed"
[ -z "${ANTHROPIC_BASE_URL+x}" ] || fail "S701 — the test's own environment gained ANTHROPIC_BASE_URL"

test_done
