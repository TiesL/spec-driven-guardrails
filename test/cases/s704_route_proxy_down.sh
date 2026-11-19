#!/usr/bin/env bash
# S704 — A down proxy refuses with exit 3 and one clear message, checks first, no silent fallback, no "`no` means direct" (#707; AC5)
# Covers: F75
#
# Seam: probe stub (SDG_ROUTE_PROBE) and, with it unset, a fake `curl` first
# on PATH; exit status, stderr, the started marker, the probe and curl logs,
# and sentinel timeout/gtimeout/nc shims that must stay uncalled; the shared
# not-yes wording checker on stderr. Each assertion is a function, run against
# the real wrapper and then against planted mutants that must turn it red
# (rc_kill).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap 'rc_listener_stop; sandbox_destroy' EXIT
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
  printf '%s\n' "$rc_err" >"$RC/message.txt"
  if [ "$rt" = codex ]; then rc_not_yes_ok "$label" "$RC/message.txt" codex
  else rc_not_yes_ok "$label" "$RC/message.txt" plain; fi
}

# --- probe stub ----------------------------------------------------------------
down_stub() { # <runtime> <status>
  echo "$2" >"$RC/probe.exit"
  run_rt "$1"
  rm -f "$RC/probe.exit"
  check_down "S704/stub/$1/$2" "$1" "$2"
  [ "$(cat "$RC/log/probe.log")" = "$CURL_ARGS" ] || fail "S704/stub/$1/$2 — probe argv: '$(cat "$RC/log/probe.log")'"
}
up_starts() { # <runtime>
  echo 0 >"$RC/probe.exit"
  run_rt "$1"
  rm -f "$RC/probe.exit"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S704/stub/$1/0 — an up probe did not start the child: exit $rc_status, stderr: $rc_err"
}
for rt in claude codex; do
  for st in 7 28 6 52 127; do down_stub "$rt" "$st"; done
  up_starts "$rt"
done

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
# order_case <label> <runtime> <setup>: with a down probe and one refusing
# condition, exit 4 and an empty probe log.
order_case() {
  local label="$1" rt="$2"
  rc_env_reset
  rc_codex_config valid
  echo 7 >"$RC/probe.exit"
  case "$3" in
    parent) rc_env_set "ANTHROPIC_BASE_URL=http://127.0.0.1:9/elsewhere" ;;
    settings) echo '{"env": {"ANTHROPIC_BASE_URL": "http://x"}}' >"$RC/cfg/settings.json" ;;
    settings-headers) echo '{"env": {"ANTHROPIC_CUSTOM_HEADERS": "x-a: 1"}}' >"$RC/cfg/settings.json" ;;
    inherited-header) rc_env_set "ANTHROPIC_CUSTOM_HEADERS=x-cave-transforms: caveman.compress.v1" ;;
    codex-config) rc_codex_config openai ;;
  esac
  case "$3" in
    codex-argument) rc_run codex -- "$RC/bin/codex" exec --oss x ;;
    codex-ignore-user-config) rc_run codex -- "$RC/bin/codex" exec --ignore-user-config x ;;
    *) run_rt "$rt" ;;
  esac
  [ "$rc_status" = 4 ] && [ "$rc_probe_calls" = 0 ] || fail "S704/order/$label — exit $rc_status with $rc_probe_calls probe calls, expected 4 with none"
  rm -f "$RC/cfg/settings.json" "$RC/probe.exit"
  rc_codex_config valid
  rc_env_reset
}
order_case parent claude parent
order_case settings claude settings
order_case settings-headers claude settings-headers
order_case inherited-header claude inherited-header
order_case codex-config codex codex-config
order_case codex-argument codex codex-argument
order_case codex-ignore-user-config codex codex-ignore-user-config

# --- no deadline helpers ---------------------------------------------------------
for s in timeout gtimeout nc; do
  [ ! -e "$RC/log/sentinel-$s" ] || fail "S704 — the wrapper called $s"
done

# --- round 4 (r1): the probe's environment ---------------------------------------
# probe_env <runtime> <e>: an up probe stub recording its environment; it
# differs from a direct run of the same stub in exactly NO_PROXY and no_proxy,
# each with the loopback appended to its own inherited value.
probe_env() {
  local label="S704/r1/$1/$2"
  rc_env_reset
  rc_proxy_env "$2"
  rc_codex_config valid
  rm -f "$RC/probe.exit"
  rc_probe_direct $CURL_ARGS
  : >"$RC/probe.recenv"
  rm -f "$RC/log/probe.env"
  run_rt "$1"
  rm -f "$RC/probe.recenv"
  [ "$rc_probe_calls" = 1 ] && [ -f "$RC/log/probe.env" ] && [ -f "$RC/probe-direct.env" ] \
    || { fail "$label — the probe did not run once with its environment recorded (exit $rc_status, $rc_probe_calls calls, stderr: $rc_err)"; rc_env_reset; return; }
  local got
  got="$(rc_env_diff "$RC/probe-direct.env" "$RC/log/probe.env")"
  [ "$got" = "$(rc_expected_loopback_diff)" ] \
    || fail "$label — the probe's environment does not differ from a direct run in exactly NO_PROXY and no_proxy: got '$got', expected '$(rc_expected_loopback_diff)'"
  rc_env_reset
}
for rt in claude codex; do
  for e in $RC_PROXY_ENVS; do probe_env "$rt" "$e"; done
done

# --- round 4 (r2): the real curl against an inherited proxy ------------------------
# A scratch listener answers HTTP 200 on L; nothing listens on P; the shim
# swaps 8787 for P and execs the real curl. With the loopback excluded, curl
# goes to P directly, is refused (7), and the listener sees nothing.
REAL_CURL="$(rc_real_curl)"
R2_READY=0
if [ -z "$REAL_CURL" ]; then
  fail "S704/r2 — no real curl found on the test's PATH outside the fixture bin"
elif ! rc_listener_start; then
  fail "S704/r2 — the scratch HTTP listener did not come up"
else
  R2_PORT="$(rc_free_port)"
  rc_curl_shim "$REAL_CURL" "$R2_PORT"
  R2_READY=1
fi
r2_env() { # <none|lower|upper>
  rc_env_reset
  rc_proxy_env e1
  rc_env_set "SDG_ROUTE_PROBE=$RC/probe/curlshim"
  rc_env_set "http_proxy=http://127.0.0.1:$RC_LISTENER_PORT"
  rc_env_set "HTTPS_PROXY=http://127.0.0.1:$RC_LISTENER_PORT"
  case "$1" in
    lower) rc_env_set "no_proxy=corp.internal" ;;
    upper) rc_env_set "NO_PROXY=corp.example" ;;
  esac
}
real_curl_down() { # <runtime> <none|lower|upper>
  local label="S704/r2/$1/$2"
  r2_env "$2"
  : >"$RC/log/listener.log"
  run_rt "$1"
  [ "$rc_status" = 3 ] || fail "$label — exit $rc_status, expected 3 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started"
  [ -z "$rc_out" ] || fail "$label — stdout is not empty: $rc_out"
  grep -qE "(^|[^0-9])7([^0-9]|$)" <<<"$rc_err" || fail "$label — the message lacks the probe exit status 7: $rc_err"
  [ ! -s "$RC/log/listener.log" ] || fail "$label — the probe went through the inherited proxy: $(cat "$RC/log/listener.log")"
  [ "$(cat "$RC/log/probe.log")" = "$CURL_ARGS" ] || fail "$label — probe argv: '$(cat "$RC/log/probe.log")'"
  rc_env_reset
}
real_curl_control() { # <none|lower|upper>: the shim run directly reaches the listener.
  local label="S704/r2/control/$1" st
  r2_env "$1"
  : >"$RC/log/listener.log"
  # shellcheck disable=SC2086
  (cd "$RC_CWD" && exec env -i "${RC_ENV[@]}" "$RC/probe/curlshim" $CURL_ARGS) >/dev/null 2>&1
  st=$?
  [ "$st" = 0 ] || fail "$label — the shim run directly exited $st, expected 0 (the fixture proxy must answer)"
  [ "$(rc_line_count "$(cat "$RC/log/listener.log")")" = 1 ] || fail "$label — the listener logged '$(cat "$RC/log/listener.log")', expected one request"
  : >"$RC/log/probe.log"
  rc_env_reset
}
if [ "$R2_READY" = 1 ]; then
  for v in none lower upper; do
    real_curl_control "$v"
    for rt in claude codex; do real_curl_down "$rt" "$v"; done
  done
fi

# --- the wording checker's own planted negative controls ---------------------------
OLD_MSG='route-child: model routing is on (WORKFLOW-ADOPTION.md: process-model-routing yes) but no HTTP answer came from http://127.0.0.1:8787 (probe exit status 7). Start the Caveman proxy, rerun with SDG_MODEL_ROUTE=off for this run, or answer process-model-routing no to opt out.'
printf '%s\n' "$OLD_MSG" >"$RC/old-claude.txt"
printf '%s Codex itself is routed by your own Codex config, which SDG does not change.\n' "$OLD_MSG" >"$RC/old-codex.txt"
rc_expect_red "S704/neg/d51ba0d-claude-message" rc_not_yes_ok neg "$RC/old-claude.txt" plain
rc_expect_red "S704/neg/d51ba0d-codex-message" rc_not_yes_ok neg "$RC/old-codex.txt" codex
echo 7 >"$RC/probe.exit"
run_rt codex
rm -f "$RC/probe.exit"
{ printf '%s\n' "$rc_err"; echo "Answer process-model-routing no to run children direct."; } >"$RC/planted.txt"
rc_expect_red "S704/neg/planted-direct-sentence" rc_not_yes_ok neg "$RC/planted.txt" codex

# --- planted mutants: each must turn its assertion red --------------------------
rc_kill "S704/kill/probe-always-up" 'probe_status=$?' 'probe_status=0' down_stub claude 7
rc_kill "S704/kill/probe-always-down" 'probe_status=$?' 'probe_status=7' up_starts claude
rc_kill "S704/kill/28-as-up" 'if [ "$probe_status" -ne 0 ]; then' \
  'if [ "$probe_status" -ne 0 ] && [ "$probe_status" -ne 28 ]; then' down_stub claude 28
rc_kill "S704/kill/52-or-127-as-up" 'if [ "$probe_status" -ne 0 ]; then' \
  'if [ "$probe_status" = 7 ] || [ "$probe_status" = 28 ]; then' down_stub codex 52
rc_kill "S704/kill/no-status-in-message" '(probe exit status $probe_status)' '(probe failed)' down_stub claude 6
rc_kill "S704/kill/silent-fallback" '  echo "$message" >&2
  exit 3' '  echo "$message" >&2
  exec "$@"' down_stub claude 7
rc_kill "S704/kill/message-without-url" 'no HTTP answer came from $PROXY_ORIGIN' 'no HTTP answer came from the proxy' down_stub claude 7
rc_kill "S704/kill/message-without-off" 'rerun with SDG_MODEL_ROUTE=off to run this one child without the route' 'rerun later' down_stub claude 7
rc_kill "S704/kill/message-without-wrapper-sentence" \
  'Answering $OPT_IN_ID no only switches this wrapper off for the project; it does not decide where a child' \
  'Answering $OPT_IN_ID no opts out; it does not decide where a child' down_stub claude 7
rc_kill "S704/kill/codex-message-without-compression-sentence" \
  'still runs there compressed;' 'still runs there;' down_stub codex 7
rc_kill "S704/kill/d51ba0d-claude-message" \
  'Start the Caveman proxy, or rerun with SDG_MODEL_ROUTE=off to run this one child without the route. Answering $OPT_IN_ID no only switches this wrapper off for the project; it does not decide where a child' \
  'Start the Caveman proxy, rerun with SDG_MODEL_ROUTE=off for this run, or answer $OPT_IN_ID no to opt out. As for where a child' \
  down_stub claude 7
rc_kill "S704/kill/message-adds-no-means-direct" \
  'it does not decide where a child' 'answer $OPT_IN_ID no to run children direct; it does not decide where a child' down_stub claude 7
probe_first='  "${SDG_ROUTE_PROBE:-curl}" -s -o /dev/null "$PROXY_ORIGIN/" >/dev/null 2>&1 || exit 3
'
CHECKS_START='if [ "$runtime" = claude ]; then
  if [ "${ANTHROPIC_BASE_URL+set}" = set ]'
rc_kill "S704/kill/probe-before-checks/settings-key" "$CHECKS_START" "${probe_first}${CHECKS_START}" order_case settings-headers claude settings-headers
rc_kill "S704/kill/probe-before-checks/inherited-header" "$CHECKS_START" "${probe_first}${CHECKS_START}" order_case inherited-header claude inherited-header
rc_kill "S704/kill/probe-before-checks/codex-argument" "$CHECKS_START" "${probe_first}${CHECKS_START}" order_case codex-argument codex codex-argument
rc_kill "S704/kill/probe-before-checks/ignore-user-config" "$CHECKS_START" "${probe_first}${CHECKS_START}" order_case codex-ignore-user-config codex codex-ignore-user-config

# Round 4 (Architect report 8): the loopback exclusion before the probe.
LB_NP='NO_PROXY="${NO_PROXY:+$NO_PROXY,}$LOOPBACK_NO_PROXY"'
LB_LNP='no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"'
PROBE_CALL='"$probe" -s -o /dev/null --connect-timeout 2 --max-time 3 "$PROXY_ORIGIN/" >/dev/null 2>&1'
LB_THEN_PROBE="$LB_NP
$LB_LNP
export NO_PROXY no_proxy
probe=\"\${SDG_ROUTE_PROBE:-curl}\"
$PROBE_CALL"
rc_kill "S704/kill/loopback-extended-after-the-probe" "$LB_THEN_PROBE" "probe=\"\${SDG_ROUTE_PROBE:-curl}\"
$PROBE_CALL
mutant_status=\$?
$LB_NP
$LB_LNP
export NO_PROXY no_proxy
(exit \$mutant_status)" probe_env codex e1
rc_kill "S704/kill/loopback-extended-after-the-probe/r2" "$LB_THEN_PROBE" "probe=\"\${SDG_ROUTE_PROBE:-curl}\"
$PROBE_CALL
mutant_status=\$?
$LB_NP
$LB_LNP
export NO_PROXY no_proxy
(exit \$mutant_status)" real_curl_down claude none
rc_kill "S704/kill/only-NO_PROXY-for-the-probe" "$LB_LNP" ':' probe_env claude e1
rc_kill "S704/kill/only-no_proxy-for-the-probe" "$LB_NP" ':' probe_env codex e1
rc_kill "S704/kill/overwrite-for-the-probe" "$LB_NP" 'NO_PROXY="$LOOPBACK_NO_PROXY"' probe_env codex e3
rc_kill "S704/kill/overwrite-for-the-probe/lower" "$LB_LNP" 'no_proxy="$LOOPBACK_NO_PROXY"' probe_env claude e2
rc_kill "S704/kill/proxy-variables-removed-instead" "$LB_THEN_PROBE" "probe=\"\${SDG_ROUTE_PROBE:-curl}\"
env -u http_proxy -u HTTPS_PROXY $PROBE_CALL" probe_env codex e2
rc_kill "S704/kill/claude-additions-before-the-probe" 'export NO_PROXY no_proxy' \
  'export NO_PROXY no_proxy
export ANTHROPIC_BASE_URL="$CLAUDE_ROUTE_URL"' probe_env claude e1
rc_kill "S704/kill/probe-argv-changed" "$PROBE_CALL" "\"\$probe\" --noproxy '*' -s -o /dev/null --connect-timeout 2 --max-time 3 \"\$PROXY_ORIGIN/\" >/dev/null 2>&1" \
  real_curl_down codex lower

test_done
