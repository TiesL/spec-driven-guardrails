#!/usr/bin/env bash
# S703 — Only the adoption answer switches routing on; the environment variable only switches it off; `off` refuses a Codex command it cannot send direct (#707; AC4)
# Covers: F75
#
# Seam: the decision matrix through the wrapper's process Interface; the probe
# log, the config hash and the direct-run comparison (environment and
# arguments). One fixture project whose answer file is rewritten per row, so
# the working directory (and PWD) is the same for the direct and the wrapped
# run. Each assertion is a function, run against the real wrapper and then
# against planted mutants that must turn it red (rc_kill).

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
TOK=tok-7f3a
mkdir -p "$RC_TOP/.claude"

# Hostile fixture: everything that would refuse if routing were on, and a
# user Codex config that routes Codex through the proxy.
hostile() {
  rc_env_set "ANTHROPIC_BASE_URL=http://127.0.0.1:9/elsewhere"
  rc_env_set "ANTHROPIC_CUSTOM_HEADERS=X-Cave-Transforms: $TOK"
  echo '{"env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:9/dead"}}' >"$RC/cfg/settings.json"
  echo '{"env": {"NO_PROXY": "corp.example"}}' >"$RC_TOP/.claude/settings.json"
  rc_codex_config valid
  echo 7 >"$RC/probe.exit"
}
clean() {
  rm -f "$RC/cfg/settings.json" "$RC_TOP/.claude/settings.json" "$RC/probe.exit"
  rc_codex_config valid
}

# set_route <value|UNSET>
set_route() {
  rc_env_del SDG_MODEL_ROUTE
  [ "$1" = UNSET ] || rc_env_set "SDG_MODEL_ROUTE=$1"
}

# --- (1) answer not yes: a pure pass-through for every value ---------------
# unchanged_run <label> <runtime> <command...>: same environment and
# arguments as a direct run, no stderr, no probe.
unchanged_run() {
  local label="$1" rt="$2"
  shift 2
  rc_direct "$@"
  rc_run "$rt" -- "$@"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "$label — not run unchanged: exit $rc_status, started $rc_started, stderr: $rc_err"; return; }
  [ -z "$(rc_env_diff)" ] || fail "$label — environment changed: $(rc_env_diff)"
  rc_args_equal_direct || fail "$label — arguments changed (no header override and no direct override may be added)"
  [ -z "$rc_err" ] || fail "$label — stderr is not empty: $rc_err"
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
}
not_yes_case() { # <answer> <value|UNSET>
  local answer="$1" value="$2" label="S703/1/$1/[$2]"
  rc_answer "$answer"
  rc_env_reset; hostile; set_route "$value"
  unchanged_run "$label/claude" claude "$claude" -p 'x y'
  unchanged_run "$label/codex" codex "$codex" exec --ephemeral 'x y'
  unchanged_run "$label/codex-listed-argument" codex "$codex" exec --profile x 'x y'
  clean
  rc_answer yes
}
values="UNSET|off|on|1|true|route||OFF|Off| off"
for answer in nofile absent no pending notes prefixed; do
  old_ifs="$IFS"; IFS='|'
  # shellcheck disable=SC2086
  set -- $values
  IFS="$old_ifs"
  for value in "$@"; do not_yes_case "$answer" "$value"; done
done

# --- (2) answer yes ---------------------------------------------------------------
yes_value_case() { # <value|UNSET>
  local value="$1" label="S703/2/yes/[$1]" claude_err codex_err e
  rc_answer yes
  rc_env_reset; clean; set_route "$value"
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
  rc_env_reset
}
for value in UNSET '' on 1 OFF Off ' off'; do yes_value_case "$value"; done

# Exact off, Claude: none of the five variables, no check, no probe.
off_claude() {
  rc_answer yes
  rc_env_reset; hostile; set_route off
  rc_env_set "NO_PROXY=corp.example"
  rc_env_set "no_proxy=corp.internal"
  unchanged_run "S703/2/off/claude" claude "$claude" -p x
  clean
  rc_env_reset
}
off_claude

# Exact off, Codex: the direct override after exec, no probe, unless the
# command or the config would route the child anyway (exit 4).
off_codex_direct() { # <config variant> <args after exec...>
  local v="$1" label="S703/2/off/codex/$1"
  shift
  rc_answer yes
  rc_env_reset; set_route off
  rc_codex_config "$v"
  echo 7 >"$RC/probe.exit"
  rc_run codex -- "$codex" exec "$@"
  rm -f "$RC/probe.exit"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "$label [$*] — not run: exit $rc_status, stderr: $rc_err"; rc_codex_config valid; return; }
  rc_args_file exec -c "$RC_CODEX_DIRECT_OVERRIDE" "$@"
  cmp -s "$RC/expected.args" "$RC/child.args" || fail "$label [$*] — arguments are not exec, -c, model_provider=\"openai\", rest"
  [ "$rc_probe_calls" = 0 ] || fail "$label [$*] — the probe ran"
  [ -z "$rc_err" ] || fail "$label [$*] — stderr: $rc_err"
  rc_codex_config valid
  rc_env_reset
}
off_codex_refused() { # <config variant> <word> <args after exec...>
  local v="$1" word="$2" label="S703/2/off/codex-refused/$1" h1
  shift 2
  rc_answer yes
  rc_env_reset; set_route off
  rc_codex_config "$v"
  h1="$(rc_tree_hash "$RC/codexhome")"
  rc_run codex -- "$codex" exec "$@"
  [ "$rc_status" = 4 ] || fail "$label [$*] — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label [$*] — the child was started"
  [ "$rc_probe_calls" = 0 ] || fail "$label [$*] — the probe ran"
  grep -qi -- "$word" <<<"$rc_err" || fail "$label [$*] — the message does not name '$word': $rc_err"
  case "$rc_err" in *"$TOK"*) fail "$label [$*] — the message prints a value: $rc_err" ;; esac
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "$label [$*] — config.toml was written"
  rc_codex_config valid
  rc_env_reset
}
off_codex_direct valid --ephemeral 'x y'
off_codex_direct missing --ephemeral 'x y'
off_codex_direct profile-direct x
off_codex_direct profile-noprovider x
off_codex_direct valid -- --profile x
off_codex_refused unparsable config.toml x
off_codex_refused unparsable pars x
off_codex_refused off-profile-caveman config.toml x
off_codex_refused off-profile-caveman caveman x
off_codex_refused off-profile-inline caveman x
off_codex_refused profile-missing missing x
off_codex_refused valid --profile --profile "$TOK" x
off_codex_refused valid --profile "--profile=$TOK" x
off_codex_refused valid -p -p "$TOK" x
off_codex_refused valid --oss --oss x
off_codex_refused valid model_provider -c "model_provider=\"$TOK\"" x
off_codex_refused valid profile "--config=profile=$TOK" x
off_codex_refused valid profiles.x.model_provider -c "profiles.x.model_provider=\"$TOK\"" x
off_codex_refused valid model_providers.caveman.base_url -c "model_providers.caveman.base_url=\"http://$TOK\"" x
# Round 3 (Architect report 7): base-URL keys in config.toml, top level and
# in the selected profile (o9)-(o12); (o13) only in an unselected profile.
off_codex_base_url() {
  off_codex_refused off-base-url-top openai_base_url x
  off_codex_refused off-base-url-top config.toml x
  off_codex_refused off-chatgpt-url-top chatgpt_base_url x
  off_codex_refused off-base-url-profile openai_base_url x
  off_codex_refused off-base-url-profile 'profile b' x
  off_codex_refused off-chatgpt-url-profile chatgpt_base_url x
  off_codex_refused off-chatgpt-url-profile config.toml x
}
off_codex_base_url
off_codex_direct off-base-url-unselected x
# The round-3 arguments refuse under off; the controls get the override.
off_codex_refused valid -p "-p$TOK" x
off_codex_refused valid model_provider "-cmodel_provider=\"caveman\"" x
off_codex_refused valid profiles -c "profiles={$TOK={}}" x
off_codex_refused valid --ignore-user-config --ignore-user-config x
off_codex_refused valid --local-provider --local-provider ollama x
off_codex_refused valid openai_base_url -c "openai_base_url=\"http://$TOK\"" x
off_codex_refused valid chatgpt_base_url -c "chatgpt_base_url=\"http://$TOK\"" x
off_codex_direct valid -- --ignore-user-config x
off_codex_direct valid -c 'model_providers_x=1' x
clean

# Round 4 (Architect report 8): under off (with (o1)) and without a yes
# answer (with the routing user config), the Codex child's environment is
# byte-identical to a direct run's in each inherited proxy environment
# (e1)-(e5): no loopback added, an inherited NO_PROXY/no_proxy kept as it was.
off_codex_env() { # <e>
  local label="S703/2/off/codex-env/$1"
  rc_answer yes
  rc_env_reset; rc_proxy_env "$1"; set_route off
  rc_codex_config valid
  echo 7 >"$RC/probe.exit"
  rc_direct "$codex" exec x
  rc_run codex -- "$codex" exec x
  rm -f "$RC/probe.exit"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "$label — not run: exit $rc_status, stderr: $rc_err"; rc_env_reset; return; }
  [ -z "$(rc_env_diff)" ] || fail "$label — the environment differs from a direct run: $(rc_env_diff)"
  rc_env_reset
}
not_yes_codex_env() { # <e>
  rc_answer no
  rc_env_reset; rc_proxy_env "$1"
  rc_codex_config valid
  unchanged_run "S703/1/no/codex-env/$1" codex "$codex" exec --ephemeral 'x y'
  rc_answer yes
  rc_env_reset
}
for e in $RC_PROXY_ENVS; do
  off_codex_env "$e"
  not_yes_codex_env "$e"
done

# Round 5 (Architect report 9): under off (with (o1)) and without a yes
# answer (with the routing user config), a Codex .env that would refuse with
# routing on, (x1) or (x4), is not read: no refusal, no stderr, no probe.
off_codex_dotenv() { # <x1|x4>
  local label="S703/2/off/codex-dotenv/$1" h1
  rc_answer yes
  rc_env_reset; set_route off
  rc_codex_config valid
  rc_codex_dotenv "$1"
  h1="$(rc_tree_hash "$RC/codexhome")"
  off_codex_direct valid --ephemeral 'x y'
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "$label — .env or config.toml was written"
  rc_dotenv_clear
  rc_env_reset
}
not_yes_codex_dotenv() { # <x1|x4>
  local h1
  rc_answer no
  rc_env_reset
  rc_codex_config valid
  rc_codex_dotenv "$1"
  h1="$(rc_tree_hash "$RC/codexhome")"
  unchanged_run "S703/1/no/codex-dotenv/$1" codex "$codex" exec --ephemeral 'x y'
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "S703/1/no/codex-dotenv/$1 — .env or config.toml was written"
  rc_dotenv_clear
  rc_answer yes
  rc_env_reset
}
for x in x1 x4; do
  off_codex_dotenv "$x"
  not_yes_codex_dotenv "$x"
done

# --- (3) launch paths: subdirectory, symlink outside the repo, $SPEC_DRIVEN_GUARDRAILS_DIR
ln -s "$RC_ROUTE" "$RC/elsewhere/rc-abs"
ln -s ../elsewhere/rc-abs "$RC/elsewhere/rc-rel" 2>/dev/null || ln -s rc-abs "$RC/elsewhere/rc-rel"
ln -s "$TEST_REPO_ROOT" "$SANDBOX/workflow"
launch_paths() {
  local launch how saved=("${RC_LAUNCH[@]}")
  rc_answer yes
  rc_env_reset
  for launch in "$RC/elsewhere/rc-abs" "$RC/elsewhere/rc-rel" "$SANDBOX/workflow/route-child.sh" "$RC_ROUTE"; do
    for how in bash shebang; do
      if [ "$how" = bash ]; then RC_LAUNCH=(/bin/bash "$launch"); else RC_LAUNCH=("$launch"); fi
      rc_direct "$claude" -p x
      rc_run claude -- "$claude" -p x
      [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "S703/3/$how/$launch — not routed (exit $rc_status, stderr: $rc_err)"
    done
  done
  RC_LAUNCH=("${saved[@]}")
}
launch_paths
# From the subdirectory and from the top level, with the launcher under test.
from_sub_and_top() {
  local where
  rc_answer yes
  rc_env_reset
  for where in "$RC_TOP/sub/dir" "$RC_TOP"; do
    RC_CWD="$where"
    rc_direct "$claude" -p x
    rc_run claude -- "$claude" -p x
    [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "S703/3/cwd=${where#"$RC"/} — not routed (exit $rc_status, stderr: $rc_err)"
  done
  RC_CWD="$RC_TOP/sub/dir"
}
from_sub_and_top

# --- (4) the answer is the working directory's project, never another one --
# The wrapper's own repository and $HOME both answer yes.
wrepo="$RC/wrapper-repo"
mkdir -p "$wrepo/lib" "$RC/nogit"
cp "$TEST_REPO_ROOT/lib/changes.sh" "$wrepo/lib/changes.sh"
git -C "$wrepo" init -q -b main
cp "$RC_TOP/WORKFLOW-ADOPTION.md" "$wrepo/WORKFLOW-ADOPTION.md"
git -C "$RC/home" init -q -b main
cp "$RC_TOP/WORKFLOW-ADOPTION.md" "$RC/home/WORKFLOW-ADOPTION.md"
other_project() {
  local where saved=("${RC_LAUNCH[@]}")
  # The wrapper under test (the real one or a planted mutant), placed in a
  # repository that answers yes.
  cp "${RC_LAUNCH[$((${#RC_LAUNCH[@]} - 1))]}" "$wrepo/route-child.sh"
  RC_LAUNCH=(/bin/bash "$wrepo/route-child.sh")
  for where in nogit project-no; do
    rc_env_reset; hostile
    if [ "$where" = nogit ]; then RC_CWD="$RC/nogit"; else RC_CWD="$RC_TOP/sub/dir"; rc_answer no; fi
    rc_direct "$claude" -p x
    rc_run claude -- "$claude" -p x
    [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S703/4/$where — not run unchanged: exit $rc_status, stderr: $rc_err"
    [ -z "$(rc_env_diff)" ] || fail "S703/4/$where — routed from another project's answer: $(rc_env_diff)"
    [ "$rc_probe_calls" = 0 ] || fail "S703/4/$where — the probe ran"
    clean
  done
  RC_CWD="$RC_TOP/sub/dir"
  rc_answer yes
  RC_LAUNCH=("${saved[@]}")
}
other_project

# --- planted mutants: each must turn its assertion red --------------------------
OPT_IN='if [ -z "$top" ] || ! answered_yes "$top" "$OPT_IN_ID"; then
  exec "$@"
fi'
OFF_IF='if [ "$route_switch" = off ]; then'
rc_kill "S703/kill/always-route" "$OPT_IN" 'if false; then exec "$@"; fi' not_yes_case no UNSET
rc_kill "S703/kill/route-on-env-value" "$OPT_IN" \
  'if [ -z "$top" ] || { ! answered_yes "$top" "$OPT_IN_ID" && [ "${SDG_MODEL_ROUTE:-}" != on ]; }; then
  exec "$@"
fi' not_yes_case no on
rc_kill "S703/kill/off-that-still-probes" "$OFF_IF" "$OFF_IF"'
  "${SDG_ROUTE_PROBE:-curl}" -s -o /dev/null "$PROXY_ORIGIN/" >/dev/null 2>&1' off_claude
rc_kill "S703/kill/off-for-Codex-still-proxied" \
  'exec "$cmd" exec -c "$CODEX_DIRECT_OVERRIDE" "$@"' 'exec "$cmd" exec -c "$CODEX_HEADER_OVERRIDE" "$@"' off_codex_direct valid x
rc_kill "S703/kill/off-without-the-Codex-selection-check" \
  '    check_codex off "$@"' '    :' off_codex_refused valid --profile --profile x x
rc_kill "S703/kill/off-without-the-Codex-selection-check/config" \
  '    check_codex off "$@"' '    :' off_codex_refused off-profile-caveman caveman x
rc_kill "S703/kill/off-check-that-refuses-a-missing-config" \
  '    if mode == "off":
        sys.exit(0)' '    if False:
        sys.exit(0)' off_codex_direct missing x
rc_kill "S703/kill/off-check-that-refuses-an-openai-profile" \
  'selected["model_provider"] != "openai"' 'selected["model_provider"] != "nobody"' off_codex_direct profile-direct x
rc_kill "S703/kill/off-check-that-reads-only-the-top-level-key" \
  'if selected is not None and "model_provider" in selected and selected["model_provider"] != "openai":' 'if False:' \
  off_codex_refused off-profile-caveman caveman x
rc_kill "S703/kill/off-check-without-inline-tables" \
  '    selected = get(data, "profiles", profile) if isinstance(profile, str) else None' \
  '    selected = get(data, "profiles", profile) if isinstance(profile, str) else None
    selected = {} if isinstance(get(data, "profiles"), Inline) else selected' \
  off_codex_refused off-profile-inline caveman x
BASE_URL_LOOP='    for key in ("openai_base_url", "chatgpt_base_url"):'
SELECTED_BASE_URL='        if selected is not None and key in selected:'
rc_kill "S703/kill/off-without-the-base-URL-check" "$BASE_URL_LOOP" '    for key in ():' off_codex_base_url
rc_kill "S703/kill/off-base-URL-check-top-level-only" "$SELECTED_BASE_URL" '        if False:' \
  off_codex_refused off-base-url-profile openai_base_url x
rc_kill "S703/kill/off-base-URL-check-in-every-profile" "$SELECTED_BASE_URL" \
  '        if any(isinstance(p, dict) and key in p for p in (get(data, "profiles") or {}).values()):' \
  off_codex_direct off-base-url-unselected x
TOP_URL_MSG='at the top level, which would send this child to another endpoint while SDG_MODEL_ROUTE=off promises it goes direct" % (named, key))'
rc_kill "S703/kill/base-URL-value-in-message" "$TOP_URL_MSG" "${TOP_URL_MSG%"% (named, key))"}% (named, data[key]))" \
  off_codex_refused off-base-url-top openai_base_url x
rc_kill "S703/kill/base-URL-value-in-message/profile" '% (named, profile, key))' '% (named, profile, selected[key]))' \
  off_codex_refused off-base-url-profile openai_base_url x
LOOPBACK_BLOCK='NO_PROXY="${NO_PROXY:+$NO_PROXY,}$LOOPBACK_NO_PROXY"
no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"
export NO_PROXY no_proxy
'
ROUTE_SWITCH='route_switch="${SDG_MODEL_ROUTE:-}"'
TOP_LINE='top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""'
rc_kill "S703/kill/loopback-extended-under-off" "$ROUTE_SWITCH" "${LOOPBACK_BLOCK}${ROUTE_SWITCH}" off_codex_env e2
rc_kill "S703/kill/loopback-extended-under-off/e5" "$ROUTE_SWITCH" "${LOOPBACK_BLOCK}${ROUTE_SWITCH}" off_codex_env e5
rc_kill "S703/kill/loopback-extended-before-the-opt-in" "$TOP_LINE" "${LOOPBACK_BLOCK}${TOP_LINE}" not_yes_codex_env e2
rc_kill "S703/kill/loopback-extended-before-the-opt-in/e1" "$TOP_LINE" "${LOOPBACK_BLOCK}${TOP_LINE}" not_yes_codex_env e1
# Round 5: the .env check run before the off branch, or before the opt-in.
DOTENV_BEFORE_OPT_IN='[ "$runtime" = codex ] && { [ ! -r "${CODEX_HOME:-$HOME/.codex}/.env" ] || grep -q "NO_PROXY" "${CODEX_HOME:-$HOME/.codex}/.env"; } && [ -e "${CODEX_HOME:-$HOME/.codex}/.env" ] && exit 4
'
for x in x1 x4; do
  rc_kill "S703/kill/dotenv-checked-under-off/$x" "$ROUTE_SWITCH" '[ "$runtime" = codex ] && check_codex_dotenv
'"$ROUTE_SWITCH" off_codex_dotenv "$x"
  rc_kill "S703/kill/dotenv-checked-before-the-opt-in/$x" "$TOP_LINE" "${DOTENV_BEFORE_OPT_IN}${TOP_LINE}" not_yes_codex_dotenv "$x"
done
rc_kill "S703/kill/not-yes-runs-the-Codex-checks" "$OPT_IN" \
  'if [ -z "$top" ] || ! answered_yes "$top" "$OPT_IN_ID"; then
  [ "$runtime" = codex ] && case " $* " in *" --profile "*) exit 4 ;; esac
  exec "$@"
fi' not_yes_case no UNSET
rc_kill "S703/kill/not-yes-adds-the-header" "$OPT_IN" \
  'if [ -z "$top" ] || ! answered_yes "$top" "$OPT_IN_ID"; then
  [ "$runtime" = codex ] && exec "$1" exec -c "$CODEX_HEADER_OVERRIDE" "${@:3}"
  exec "$@"
fi' not_yes_case no UNSET
rc_kill "S703/kill/case-insensitive-off" "$OFF_IF" \
  'if [ "$(printf %s "$route_switch" | tr A-Z a-z)" = off ]; then' yes_value_case OFF
rc_kill "S703/kill/trim-then-off" "$OFF_IF" \
  'if [ "$(printf %s "$route_switch" | tr -d " ")" = off ]; then' yes_value_case ' off'
rc_kill "S703/kill/silent-ignore" 'if [ -n "$route_switch" ]; then' 'if false; then' yes_value_case on
rc_kill "S703/kill/line-when-routing-off" "$OPT_IN" \
  'if [ -z "$top" ] || ! answered_yes "$top" "$OPT_IN_ID"; then
  [ -n "${SDG_MODEL_ROUTE:-}" ] && echo "route-child: SDG_MODEL_ROUTE is ignored" >&2
  exec "$@"
fi' not_yes_case no on
rc_kill "S703/kill/cwd-instead-of-top-level" \
  'top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""' 'top="$PWD"' from_sub_and_top
rc_kill "S703/kill/repository-of-the-wrapper-instead-of-project" \
  'top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""' 'top="$script_dir"' other_project
rc_kill "S703/kill/notes-column-counts" '! answered_yes "$top" "$OPT_IN_ID"' \
  '! grep -qE "^\| process-model-routing \|.*yes" "$top/WORKFLOW-ADOPTION.md"' not_yes_case notes UNSET
rc_kill "S703/kill/id-prefix-counts" '! answered_yes "$top" "$OPT_IN_ID"' \
  '! grep -qE "^\| process-model-routing[^|]* \| yes" "$top/WORKFLOW-ADOPTION.md"' not_yes_case prefixed UNSET
rc_kill "S703/kill/reimplemented-parser" '! answered_yes "$top" "$OPT_IN_ID"' \
  '! grep -q "process-model-routing.*yes" "$top/WORKFLOW-ADOPTION.md"' not_yes_case notes UNSET

test_done
