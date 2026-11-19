#!/usr/bin/env bash
# S703 — Only the adoption answer switches routing on; the environment variable only switches it off (#707; AC4)
# Covers: F75
#
# Seam: the decision matrix through the wrapper's process Interface; the probe
# log and the direct-run comparison (environment and arguments). One fixture
# project whose answer file is rewritten per row, so the working directory
# (and PWD) is the same for the direct and the wrapped run.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S703 — route-child.sh is missing or not executable"; test_done; }

claude="$RC/bin/claude"
codex="$RC/bin/codex"

# Hostile fixture: everything that would refuse or route if routing were on.
hostile() {
  rc_env_set "ANTHROPIC_BASE_URL=http://127.0.0.1:9/elsewhere"
  echo '{"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:9/dead"}}' >"$RC/cfg/settings.json"
  rc_codex_config openai
  echo 7 >"$RC/probe.exit"
}
clean() {
  rm -f "$RC/cfg/settings.json" "$RC/probe.exit"
  rc_codex_config valid
}

# set_route <value|UNSET>
set_route() {
  rc_env_del SDG_MODEL_ROUTE
  [ "$1" = UNSET ] || rc_env_set "SDG_MODEL_ROUTE=$1"
}

# --- (1) answer not yes: a pure pass-through for every value ---------------
values="UNSET|off|on|1|true|route||OFF|Off| off"
for answer in nofile absent no pending notes prefixed; do
  rc_answer "$answer"
  old_ifs="$IFS"; IFS='|'
  for value in $values; do
    IFS="$old_ifs"
    rc_env_reset; hostile; set_route "$value"
    for rt in claude codex; do
      if [ "$rt" = claude ]; then cmd=("$claude" -p 'x y'); else cmd=("$codex" exec --ephemeral 'x y'); fi
      rc_direct "${cmd[@]}"
      rc_run "$rt" -- "${cmd[@]}"
      label="S703/1/$answer/[$value]/$rt"
      [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "$label — not run unchanged: exit $rc_status, started $rc_started, stderr: $rc_err"
      [ -z "$(rc_env_diff)" ] || fail "$label — environment changed: $(rc_env_diff)"
      rc_args_equal_direct || fail "$label — arguments changed"
      [ -z "$rc_err" ] || fail "$label — stderr is not empty: $rc_err"
      [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
    done
    IFS='|'
  done
  IFS="$old_ifs"
  clean
done

# --- (2) answer yes ---------------------------------------------------------------
rc_answer yes
for value in UNSET '' on 1 OFF Off ' off'; do
  rc_env_reset; clean; set_route "$value"
  label="S703/2/yes/[$value]"
  rc_direct "$claude" -p x
  rc_run claude -- "$claude" -p x
  [ "$rc_started" = 1 ] || fail "$label/claude — not started: exit $rc_status, stderr: $rc_err"
  [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "$label/claude — not routed: $(rc_env_diff)"
  claude_err="$rc_err"
  rc_run codex -- "$codex" exec x
  rc_args_file exec -c "$RC_CODEX_HEADER_OVERRIDE" x
  cmp -s "$RC/expected.args" "$RC/child.args" || fail "$label/codex — not routed (no header override after exec)"
  codex_err="$rc_err"
  case "$value" in
    UNSET|'')
      [ -z "$claude_err" ] || fail "$label/claude — unexpected stderr: $claude_err"
      [ -z "$codex_err" ] || fail "$label/codex — unexpected stderr: $codex_err" ;;
    *)
      for e in "$claude_err" "$codex_err"; do
        [ "$(rc_line_count "$e")" = 1 ] || fail "$label — expected exactly one stderr line for an ignored value, got: '$e'"
        grep -q 'off' <<<"$e" || fail "$label — the stderr line does not say that only off switches off: $e"
        grep -q 'SDG_MODEL_ROUTE' <<<"$e" || fail "$label — the stderr line does not name SDG_MODEL_ROUTE: $e"
      done ;;
  esac
done

# Exact off: no routing, no probe, no checks, Codex goes direct.
rc_env_reset; hostile; set_route off
rc_direct "$claude" -p x
rc_run claude -- "$claude" -p x
[ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S703/2/off/claude — not run: exit $rc_status, stderr: $rc_err"
[ -z "$(rc_env_diff)" ] || fail "S703/2/off/claude — a routing variable was added: $(rc_env_diff)"
rc_args_equal_direct || fail "S703/2/off/claude — arguments changed"
[ "$rc_probe_calls" = 0 ] || fail "S703/2/off/claude — the probe ran"
[ -z "$rc_err" ] || fail "S703/2/off/claude — stderr: $rc_err"
rc_env_set "NO_PROXY=corp.example"
rc_env_set "ANTHROPIC_CUSTOM_HEADERS=x-keep: 1"
rc_direct "$claude" -p x
rc_run claude -- "$claude" -p x
[ -z "$(rc_env_diff)" ] || fail "S703/2/off/claude — inherited NO_PROXY or headers changed: $(rc_env_diff)"
rc_direct "$codex" exec --ephemeral 'x y'
rc_run codex -- "$codex" exec --ephemeral 'x y'
[ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S703/2/off/codex — not run: exit $rc_status, stderr: $rc_err"
rc_args_file exec -c "$RC_CODEX_DIRECT_OVERRIDE" --ephemeral 'x y'
cmp -s "$RC/expected.args" "$RC/child.args" || fail "S703/2/off/codex — arguments are not exec, -c, model_provider=\"openai\", rest"
[ -z "$(rc_env_diff)" ] || fail "S703/2/off/codex — environment changed: $(rc_env_diff)"
[ "$rc_probe_calls" = 0 ] || fail "S703/2/off/codex — the probe ran"
clean

# --- (3) launch paths: subdirectory, symlink outside the repo, $SPEC_DRIVEN_GUARDRAILS_DIR
rc_env_reset
ln -s "$RC_ROUTE" "$RC/elsewhere/rc-abs"
ln -s ../elsewhere/rc-abs "$RC/elsewhere/rc-rel" 2>/dev/null || ln -s rc-abs "$RC/elsewhere/rc-rel"
ln -s "$TEST_REPO_ROOT" "$SANDBOX/workflow"
for launch in "$RC/elsewhere/rc-abs" "$RC/elsewhere/rc-rel" "$SANDBOX/workflow/route-child.sh" "$RC_ROUTE"; do
  for how in bash shebang; do
    if [ "$how" = bash ]; then RC_LAUNCH=(/bin/bash "$launch"); else RC_LAUNCH=("$launch"); fi
    rc_direct "$claude" -p x
    rc_run claude -- "$claude" -p x
    [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "S703/3/$how/$launch — not routed (exit $rc_status, stderr: $rc_err)"
  done
done
RC_LAUNCH=(/bin/bash "$RC_ROUTE")
# From the top level as well as from the subdirectory.
RC_CWD="$RC_TOP"
rc_direct "$claude" -p x
rc_run claude -- "$claude" -p x
[ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "S703/3/top — not routed from the top level"
RC_CWD="$RC_TOP/sub/dir"

# --- (4) the answer is the working directory's project, never another one --
# The wrapper's own repository and $HOME both answer yes.
wrepo="$RC/wrapper-repo"
mkdir -p "$wrepo/lib"
cp "$RC_ROUTE" "$wrepo/route-child.sh"
cp "$TEST_REPO_ROOT/lib/changes.sh" "$wrepo/lib/changes.sh"
git -C "$wrepo" init -q -b main
cp "$RC_TOP/WORKFLOW-ADOPTION.md" "$wrepo/WORKFLOW-ADOPTION.md"
git -C "$RC/home" init -q -b main
cp "$RC_TOP/WORKFLOW-ADOPTION.md" "$RC/home/WORKFLOW-ADOPTION.md"
RC_LAUNCH=(/bin/bash "$wrepo/route-child.sh")
mkdir -p "$RC/nogit"
for where in nogit project-no; do
  rc_env_reset; hostile
  if [ "$where" = nogit ]; then RC_CWD="$RC/nogit"; else RC_CWD="$RC_TOP/sub/dir"; rc_answer no; fi
  rc_direct "$claude" -p x
  rc_run claude -- "$claude" -p x
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S703/4/$where — not run unchanged: exit $rc_status, stderr: $rc_err"
  [ -z "$(rc_env_diff)" ] || fail "S703/4/$where — routed from another project's answer: $(rc_env_diff)"
  [ "$rc_probe_calls" = 0 ] || fail "S703/4/$where — the probe ran"
done

test_done
