#!/usr/bin/env bash
# S701 — A routed Claude child gets exactly five additions, an inherited transform header refuses, and nothing the parent reads changes (#707; AC2)
# Covers: F75
#
# Seam: route-child.sh run as a process (test/fixtures/route-child-helpers.sh):
# stub child, probe stub, the environment diff against the same stub run
# directly, and one tree hash over everything the parent reads. Answer yes,
# probe up, clean fixture settings. Each assertion is a function, run against
# the real wrapper and then against planted mutants that must turn it red
# (rc_kill). The parent's own environment needs no assertion: the wrapper
# `exec`s its command, and no child can change its parent's environment.

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

# Clean settings in every checked location (none of the five keys under env),
# and the dotfiles a parent shell reads.
mkdir -p "$RC_TOP/.claude" "$RC_CWD/.claude" "$RC/home/.claude"
echo '{"permissions": {"allow": []}}' >"$RC/cfg/settings.json"
echo '{}' >"$RC_TOP/.claude/settings.json"
echo '{"env": {"FOO": "1"}}' >"$RC_TOP/.claude/settings.local.json"
echo '{"hooks": {}}' >"$RC_CWD/.claude/settings.json"
echo '{}' >"$RC/home/.claude/settings.json"
for f in .zshrc .bashrc .profile; do echo "# fixture $f" >"$RC/home/$f"; done

stub="$RC/bin/claude"
args=(-p 'a prompt with spaces' "q'uote\"d" '' -- --model x)
TOK=tok-7f3a

# routed_case <label> <NO_PROXY> <headers> <no_proxy> [NAME=value...]: one
# routed run with the given inherited variables; the diff must be exactly the
# five additions over those inherited values.
routed_case() {
  local label="$1" np="$2" hd="$3" lnp="$4" got want e
  shift 4
  rc_env_reset
  for e in "$@"; do rc_env_set "$e"; done
  rc_direct "$stub" "${args[@]}"
  rc_run claude -- "$stub" "${args[@]}"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "S701/$label — not started: exit $rc_status, stderr: $rc_err"; return; }
  got="$(rc_env_diff)"
  want="$(rc_expected_claude_diff "$np" "$hd" "$lnp")"
  [ "$got" = "$want" ] || fail "S701/$label — environment differs from a direct run by:
$got
expected exactly:
$want"
  rc_args_equal_direct || fail "S701/$label — the arguments were changed (no --bare, --setting-sources or --settings may be added)"
  [ -z "$rc_out" ] || fail "S701/$label — the wrapper printed on stdout: $rc_out"
}

routed_a() {
  routed_case a '' '' ''
  [ "$(cat "$RC/log/probe.log")" = "-s -o /dev/null --connect-timeout 2 --max-time 3 http://127.0.0.1:8787/" ] \
    || fail "S701/a — the probe was not called once with the curl arguments: '$(cat "$RC/log/probe.log")'"
}
routed_b() {
  routed_case b corp.example 'x-keep: 1' corp.internal \
    "NO_PROXY=corp.example" "no_proxy=corp.internal" "ANTHROPIC_CUSTOM_HEADERS=x-keep: 1" \
    "ANTHROPIC_API_KEY=k" "CLAUDECODE=1" "CLAUDE_CODE_SESSION_ID=s"
}
routed_c() {
  routed_case c '' '' corp.internal \
    "http_proxy=http://corp:3128" "HTTPS_PROXY=http://corp:3128" "no_proxy=corp.internal"
}
routed_d() {
  routed_case d corp.example '' '' \
    "http_proxy=http://corp:3128" "HTTPS_PROXY=http://corp:3128" "NO_PROXY=corp.example"
}
routed_e() { routed_case e '' '' '' "NO_PROXY=" "no_proxy="; }
routed_g() {
  routed_case g1 '' 'x-other: 1' '' "ANTHROPIC_CUSTOM_HEADERS=x-other: 1"
  routed_case g2 '' "x-cave-transforms-extra: $TOK" '' "ANTHROPIC_CUSTOM_HEADERS=x-cave-transforms-extra: $TOK"
  routed_case g3 '' "x-keep: x-cave-transforms: $TOK" '' "ANTHROPIC_CUSTOM_HEADERS=x-keep: x-cave-transforms: $TOK"
}

# (f) inherited transform-header conflicts.
conflicts=(
  "X-Cave-Transforms: caveman.compress.v1-$TOK"
  "x-cave-transforms:$TOK"
  "  x-cave-transforms  : $TOK"
  "x-keep: 1
x-CAVE-transforms: $TOK"
  "x-cave-transforms: caveman.pass-through.v1"
)
# refused_one <headers> <up|down>: the routed run refuses before the probe,
# naming the variable and the header, never the value.
refused_one() {
  local h="$1" probe="$2" label
  rc_env_reset
  rc_env_set "ANTHROPIC_CUSTOM_HEADERS=$h"
  if [ "$probe" = down ]; then echo 7 >"$RC/probe.exit"; else rm -f "$RC/probe.exit"; fi
  rc_run claude -- "$stub" -p x
  rm -f "$RC/probe.exit"
  label="S701/f/$probe/[$(printf '%s' "$h" | tr '\n' '|')]"
  [ "$rc_status" = 4 ] || fail "$label — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started"
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran before the header check"
  case "$rc_err" in *ANTHROPIC_CUSTOM_HEADERS*x-cave-transforms*|*x-cave-transforms*ANTHROPIC_CUSTOM_HEADERS*) ;;
    *) fail "$label — the message does not name ANTHROPIC_CUSTOM_HEADERS and x-cave-transforms: $rc_err" ;; esac
  case "$rc_err" in *"$TOK"*|*caveman.compress.v1*) fail "$label — the message prints the header value: $rc_err" ;; esac
  rc_env_reset
}
# unchanged_one <headers> <not-yes|off>: no refusal, the child runs unchanged.
unchanged_one() {
  local h="$1" how="$2" label
  rc_env_reset
  rc_env_set "ANTHROPIC_CUSTOM_HEADERS=$h"
  if [ "$how" = off ]; then rc_env_set "SDG_MODEL_ROUTE=off"; else rc_answer no; fi
  rc_direct "$stub" -p x
  rc_run claude -- "$stub" -p x
  rc_answer yes
  label="S701/f/$how/[$(printf '%s' "$h" | tr '\n' '|')]"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "$label — not run unchanged: exit $rc_status, stderr: $rc_err"
  [ -z "$(rc_env_diff)" ] || fail "$label — environment changed: $(rc_env_diff)"
  [ -z "$rc_err" ] || fail "$label — stderr is not empty: $rc_err"
  rc_env_reset
}

assert_exit_status() {
  local code
  for code in 0 1 3 4 130; do
    rc_env_reset
    rc_env_set "STUB_EXIT=$code"
    rc_run claude -- "$stub" -p x
    [ "$rc_status" = "$code" ] || fail "S701/exit — the child exited $code, the wrapper exited $rc_status"
    [ "$rc_started" = 1 ] || fail "S701/exit — the child was not started for STUB_EXIT=$code"
  done
  rc_env_reset
}

# Nothing the parent reads changes: one tree hash over HOME (dotfiles and
# .claude/ included), CLAUDE_CONFIG_DIR, CODEX_HOME, the managed-settings
# directory and the project tree (the working directory is inside it).
parent_tree() { rc_tree_hash "$RC/home" "$RC/cfg" "$RC/codexhome" "$RC/managed" "$RC_TOP"; }
assert_parent_untouched() {
  local before after
  before="$(parent_tree)"
  rc_env_reset
  rc_run claude -- "$stub" "${args[@]}"
  rc_env_set "NO_PROXY=corp.example"
  rc_env_set "ANTHROPIC_CUSTOM_HEADERS=x-keep: 1"
  rc_run claude -- "$stub" "${args[@]}"
  rc_env_reset
  after="$(parent_tree)"
  [ "$before" = "$after" ] || fail "S701/tree — a file the parent reads (HOME, settings, CODEX_HOME, managed, project) changed or was added"
}

for f in routed_a routed_b routed_c routed_d routed_e routed_g; do "$f"; done
for h in "${conflicts[@]}"; do
  refused_one "$h" up
  refused_one "$h" down
  unchanged_one "$h" not-yes
  unchanged_one "$h" off
done
assert_exit_status
assert_parent_untouched

# --- planted mutants: each must turn its assertion red --------------------------
END_EXEC='export $CLAUDE_CHILD_VARS
exec "$@"'
rc_kill "S701/kill/overwrite-NO_PROXY" \
  'NO_PROXY="${NO_PROXY:+$NO_PROXY,}$LOOPBACK_NO_PROXY"' 'NO_PROXY="$LOOPBACK_NO_PROXY"' routed_b
rc_kill "S701/kill/overwrite-no_proxy" \
  'no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"' 'no_proxy="$LOOPBACK_NO_PROXY"' routed_b
rc_kill "S701/kill/overwrite-headers" \
  'ANTHROPIC_CUSTOM_HEADERS="${ANTHROPIC_CUSTOM_HEADERS:+' 'ANTHROPIC_CUSTOM_HEADERS="$TRANSFORM_HEADER" #' routed_b
rc_kill "S701/kill/uppercase-only-NO_PROXY" \
  'no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"' ':' routed_c
rc_kill "S701/kill/no_proxy-from-NO_PROXY" \
  'no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"' 'no_proxy="$NO_PROXY"' routed_c
rc_kill "S701/kill/extra-variable" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
export SDG_EXTRA=1
exec "$@"' routed_a
rc_kill "S701/kill/missing-first-party-flag" \
  ' _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL ' ' ' routed_a
rc_kill "S701/kill/bare-injected" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
exec "$@" --bare' routed_a
rc_kill "S701/kill/setting-sources-injected" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
exec "$@" --setting-sources ""' routed_a
rc_kill "S701/kill/argument-resplitting" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
exec $*' routed_a
rc_kill "S701/kill/header-check-case-sensitive" \
  " | tr '[:upper:]' '[:lower:]')\"" ')"' refused_one "${conflicts[0]}" up
rc_kill "S701/kill/header-check-first-line-only" \
  '[ "$name" = "$TRANSFORM_NAME" ] && return 0' '[ "$name" = "$TRANSFORM_NAME" ] && return 0; return 1' refused_one "${conflicts[3]}" up
rc_kill "S701/kill/header-check-substring" \
  '  local line name
  while IFS= read -r line' '  local line name
  case "${ANTHROPIC_CUSTOM_HEADERS:-}" in *[xX]-[cC][aA][vV][eE]-[tT]*) return 0 ;; esac
  while IFS= read -r line' routed_g
rc_kill "S701/kill/refusal-prints-value" \
  'already has an $TRANSFORM_NAME header,' 'already has an $TRANSFORM_NAME header ($ANTHROPIC_CUSTOM_HEADERS),' refused_one "${conflicts[0]}" up
rc_kill "S701/kill/header-check-after-probe" \
  '  if inherited_transform_header; then' '  "${SDG_ROUTE_PROBE:-curl}" -s -o /dev/null "$PROXY_ORIGIN/" >/dev/null 2>&1 || exit 3
  if inherited_transform_header; then' refused_one "${conflicts[0]}" down
rc_kill "S701/kill/settings-write" \
  '  user_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"' '  user_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; : >"$user_dir/settings.json.sdg"' assert_parent_untouched
rc_kill "S701/kill/zshrc-export" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
echo "export ANTHROPIC_BASE_URL=$CLAUDE_ROUTE_URL" >>"$HOME/.zshrc"
exec "$@"' assert_parent_untouched
rc_kill "S701/kill/home-claude-settings-env" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
echo "{\"env\":{\"ANTHROPIC_BASE_URL\":\"$CLAUDE_ROUTE_URL\"}}" >"$HOME/.claude/settings.json"
exec "$@"' assert_parent_untouched
rc_kill "S701/kill/envrc-in-cwd" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
echo "export ANTHROPIC_BASE_URL=$CLAUDE_ROUTE_URL" >.envrc
exec "$@"' assert_parent_untouched
rc_kill "S701/kill/exit-status-remapped" "$END_EXEC" 'export $CLAUDE_CHILD_VARS
"$@"; exit 0' assert_exit_status

test_done
