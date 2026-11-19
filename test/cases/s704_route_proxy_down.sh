#!/usr/bin/env bash
# S704 — A down proxy refuses with exit 3 and one clear message, checks first, no silent fallback (#707; AC5)
# Covers: F75
#
# Seam: probe stub (SDG_ROUTE_PROBE) and, with it unset, a fake `curl` first
# on PATH; exit status, stderr, the started marker, the probe and curl logs,
# and sentinel timeout/gtimeout/nc shims that must stay uncalled.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S704 — route-child.sh is missing or not executable"; test_done; }

CURL_ARGS="-s -o /dev/null --connect-timeout 2 --max-time 3 http://127.0.0.1:8787/"

run_rt() { # <runtime>
  if [ "$1" = claude ]; then rc_run claude -- "$RC/bin/claude" -p x
  else rc_run codex -- "$RC/bin/codex" exec x; fi
}

check_down() { # <label> <runtime> <status>
  local label="$1" rt="$2" st="$3"
  [ "$rc_status" = 3 ] || fail "$label — exit $rc_status, expected 3 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started (no fallback allowed)"
  [ -z "$rc_out" ] || fail "$label — stdout is not empty: $rc_out"
  [ "$(rc_line_count "$rc_err")" = 1 ] || fail "$label — expected one stderr message line, got: $rc_err"
  local need
  for need in "http://127.0.0.1:8787" "SDG_MODEL_ROUTE=off" "process-model-routing" " no"; do
    case "$rc_err" in *"$need"*) ;; *) fail "$label — the message lacks '$need': $rc_err" ;; esac
  done
  grep -qE "(^|[^0-9])$st([^0-9]|$)" <<<"$rc_err" || fail "$label — the message lacks the probe exit status $st: $rc_err"
  if [ "$rt" = codex ]; then
    grep -q 'Codex config' <<<"$rc_err" || fail "$label — the Codex message does not say Codex is routed by the user's own Codex config: $rc_err"
  fi
}

# --- probe stub ----------------------------------------------------------------
for rt in claude codex; do
  for st in 7 28 6 52 127; do
    echo "$st" >"$RC/probe.exit"
    run_rt "$rt"
    check_down "S704/stub/$rt/$st" "$rt" "$st"
    [ "$(cat "$RC/log/probe.log")" = "$CURL_ARGS" ] || fail "S704/stub/$rt/$st — probe argv: '$(cat "$RC/log/probe.log")'"
  done
  echo 0 >"$RC/probe.exit"
  run_rt "$rt"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S704/stub/$rt/0 — an up probe did not start the child: exit $rc_status, stderr: $rc_err"
done
rm -f "$RC/probe.exit"

# --- curl from PATH (SDG_ROUTE_PROBE unset, and set but empty) --------------
for how in unset empty; do
  rc_env_reset
  if [ "$how" = unset ]; then rc_env_del SDG_ROUTE_PROBE; else rc_env_set "SDG_ROUTE_PROBE="; fi
  for rt in claude codex; do
    for st in 7 28 52 127 0; do
      echo "$st" >"$RC/curl.exit"
      : >"$RC/log/curl.log"
      run_rt "$rt"
      [ "$(cat "$RC/log/curl.log")" = "$CURL_ARGS" ] || fail "S704/curl-$how/$rt/$st — curl argv: '$(cat "$RC/log/curl.log")'"
      if [ "$st" = 0 ]; then
        [ "$rc_started" = 1 ] || fail "S704/curl-$how/$rt/0 — an HTTP answer did not start the child: $rc_err"
      else
        check_down "S704/curl-$how/$rt/$st" "$rt" "$st"
      fi
    done
  done
done
rc_env_reset

# --- checks come before the probe ------------------------------------------------
echo 7 >"$RC/probe.exit"
rc_env_set "ANTHROPIC_BASE_URL=http://127.0.0.1:9/elsewhere"
rc_run claude -- "$RC/bin/claude" -p x
[ "$rc_status" = 4 ] && [ "$rc_probe_calls" = 0 ] || fail "S704/order/parent — exit $rc_status with $rc_probe_calls probe calls, expected 4 with none"
rc_env_reset
echo '{"env": {"ANTHROPIC_BASE_URL": "http://x"}}' >"$RC/cfg/settings.json"
rc_run claude -- "$RC/bin/claude" -p x
[ "$rc_status" = 4 ] && [ "$rc_probe_calls" = 0 ] || fail "S704/order/settings — exit $rc_status with $rc_probe_calls probe calls, expected 4 with none"
rm -f "$RC/cfg/settings.json"
rc_codex_config openai
rc_run codex -- "$RC/bin/codex" exec x
[ "$rc_status" = 4 ] && [ "$rc_probe_calls" = 0 ] || fail "S704/order/codex-config — exit $rc_status with $rc_probe_calls probe calls, expected 4 with none"
rc_codex_config valid
rm -f "$RC/probe.exit"

# --- no deadline helpers ---------------------------------------------------------
for s in timeout gtimeout nc; do
  [ ! -e "$RC/log/sentinel-$s" ] || fail "S704 — the wrapper called $s"
done

test_done
