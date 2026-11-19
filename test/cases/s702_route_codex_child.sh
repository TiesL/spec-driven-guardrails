#!/usr/bin/env bash
# S702 — A routed Codex child gets the header after `exec`; the effective provider, the header in any TOML form and the command's own selection arguments are checked; usage errors exit 2 in every mode (#707; AC3, AC4 usage half)
# Covers: F75
#
# Seam: route-child.sh as a process with a stub named `codex`, a fixture
# CODEX_HOME/config.toml per variant (hashed before and after), the probe stub.
# Each assertion is a function, run against the real wrapper and then against
# planted mutants that must turn it red (rc_kill).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S702 — route-child.sh is missing or not executable"; test_done; }

codex="$RC/bin/codex"
prompt='a prompt with spaces'
TOK=tok-7f3a

# routes <label> <config variant> <args after exec...>: the child gets exec,
# -c, the header override, then the original rest byte for byte; its
# environment differs from a direct run's in exactly NO_PROXY and no_proxy
# (round 4), for the inherited proxy environment $PENV (default e1); one
# probe call; config.toml unchanged.
PENV=e1
routes() {
  local label="$1" v="$2" h1
  shift 2
  rc_env_reset
  rc_proxy_env "$PENV"
  rc_codex_config "$v"
  h1="$(rc_tree_hash "$RC/codexhome")"
  rc_direct "$codex" exec "$@"
  rc_run codex -- "$codex" exec "$@"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "S702/$label — not routed: exit $rc_status, started $rc_started, stderr: $rc_err"; return; }
  rc_args_file exec -c "$RC_CODEX_HEADER_OVERRIDE" "$@"
  cmp -s "$RC/expected.args" "$RC/child.args" \
    || fail "S702/$label — arguments are not: exec, -c, the header override, then the original rest"
  [ "$(rc_env_diff)" = "$(rc_expected_loopback_diff)" ] \
    || fail "S702/$label/$PENV — the environment does not differ from a direct run in exactly NO_PROXY and no_proxy (the loopback appended): got '$(rc_env_diff)', expected '$(rc_expected_loopback_diff)'"
  [ "$rc_probe_calls" = 1 ] || fail "S702/$label — the probe ran $rc_probe_calls times, expected once"
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "S702/$label — config.toml was written"
}

# refused_config <variant> <word...>: exit 4, no child, no probe, a message
# naming config.toml and each word (case-insensitive), the file unchanged.
refused_config() {
  local v="$1" h1 word
  shift
  rc_env_reset
  rc_codex_config "$v"
  h1="$(rc_tree_hash "$RC/codexhome")"
  rc_run codex -- "$codex" exec --ephemeral "$prompt"
  [ "$rc_status" = 4 ] || fail "S702/$v — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "S702/$v — the child was started"
  case "$rc_err" in *config.toml*) ;; *) fail "S702/$v — the message does not name config.toml: $rc_err" ;; esac
  for word in "$@"; do
    grep -qi -- "$word" <<<"$rc_err" || fail "S702/$v — the message does not give the cause ('$word'): $rc_err"
  done
  [ "$rc_probe_calls" = 0 ] || fail "S702/$v — the probe ran before the config check refused"
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "S702/$v — config.toml was written"
}

# refused_arg <name[,name...]> <up|down> <args after exec...>: with the valid
# config, exit 4, no child, no probe, a message naming each <name> (the
# option, and for -c/--config the key or its first segment) and not the
# value token.
refused_arg() {
  local names="$1" probe="$2" label name
  shift 2
  label="S702/arg/$probe/[$*]"
  rc_env_reset
  rc_codex_config valid
  if [ "$probe" = down ]; then echo 7 >"$RC/probe.exit"; else rm -f "$RC/probe.exit"; fi
  rc_run codex -- "$codex" exec "$@" "$prompt"
  rm -f "$RC/probe.exit"
  [ "$rc_status" = 4 ] || fail "$label — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started"
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran before the argument check"
  local old_ifs="$IFS"
  IFS=,
  # shellcheck disable=SC2086
  set -- $names
  IFS="$old_ifs"
  for name in "$@"; do
    case "$rc_err" in *"$name"*) ;; *) fail "$label — the message does not name '$name': $rc_err" ;; esac
  done
  case "$rc_err" in *"$TOK"*) fail "$label — the message prints the value: $rc_err" ;; esac
}

# --- config variants -----------------------------------------------------------
routed_configs() {
  routes valid valid --ephemeral "$prompt"
  routes e-header-other header-other --ephemeral "$prompt"
  routes h-profile-table-unselected profile --ephemeral "$prompt"
  routes j-profile-selects-caveman profile-cv --ephemeral "$prompt"
  routes l-profile-without-provider profile-noprovider --ephemeral "$prompt"
  routes t-inline-both-providers inline-both --ephemeral "$prompt"
}
routed_configs
refused_config openai caveman
refused_config nokey caveman
refused_config comment caveman
refused_config header http_headers
refused_config unparsable pars
refused_config missing caveman
refused_config profile-direct direct caveman
refused_config profile-missing missing profile
refused_config profile-inline profile caveman
refused_config profile-dotted profile caveman
for v in inline-provider providers-table dotted-provider header-subtable; do
  refused_config "$v" http_headers
done
for v in header inline-provider providers-table dotted-provider header-subtable; do
  refused_config "$v-env" env_http_headers
done

# --- the command's own selection arguments -----------------------------------
selection_args() { # one line per case: <name>|<args, NUL-free, separated by \t>
  printf '%s\n' \
    "--profile|--profile	$TOK" \
    "--profile|--profile=$TOK" \
    "-p|-p	$TOK" \
    "-p|-p=$TOK" \
    "--oss|--oss" \
    "model_provider|-c	model_provider=\"$TOK\"" \
    "model_provider|-c=model_provider=$TOK" \
    "model_provider|--config	model_provider=\"$TOK\"" \
    "profile|--config=profile=$TOK" \
    "profile|-c	profile=\"$TOK\"" \
    "profiles.x.model_provider|-c	profiles.x.model_provider=\"$TOK\"" \
    "model_providers.caveman.http_headers|-c	model_providers.caveman.http_headers={\"x-a\"=\"$TOK\"}" \
    "model_providers.caveman.base_url|-c	model_providers.caveman.base_url=\"http://$TOK\"" \
    "model_providers|-c	model_providers={}" \
    "model_provider|-c	 model_provider = \"$TOK\"" \
    "model_provider|-c	\"model_provider\"=\"$TOK\""
  round3_args
}
# Round 3 (Architect report 7): attached forms, whole-table and quoted first
# segments, the two new options, the two base-URL keys, the value of an
# option the list does not know.
round3_args() {
  printf '%s\n' \
    "-p|-p$TOK" \
    "-c,model_provider|-cmodel_provider=\"$TOK\"" \
    "-c,profile|-c\"profile\"=\"$TOK\"" \
    "-c,profiles|-c	profiles={$TOK={}}" \
    "--config,profiles|--config=profiles={$TOK={}}" \
    "-c,profiles|-c	 \"profiles\" .x.model_provider=\"$TOK\"" \
    "--ignore-user-config|--ignore-user-config" \
    "--local-provider|--local-provider	$TOK" \
    "--local-provider|--local-provider=$TOK" \
    "-c,openai_base_url|-c	openai_base_url=\"http://$TOK\"" \
    "--config,openai_base_url|--config=openai_base_url=http://$TOK" \
    "-c,chatgpt_base_url|-c	chatgpt_base_url=\"http://$TOK\"" \
    "-c,chatgpt_base_url|-cchatgpt_base_url=http://$TOK" \
    "--oss|-o	--oss"
}
refused_line() { # <line> <up|down>
  local name="${1%%|*}" rest="${1#*|}" parts=()
  IFS=$'\t' read -r -a parts <<<"$rest"
  refused_arg "$name" "$2" "${parts[@]}"
}
while IFS= read -r line; do
  refused_line "$line" up
  refused_line "$line" down
done <<<"$(selection_args)"

# Argument controls that must route.
routed_args() {
  routes arg-model valid -c 'model="gpt-5"' "$prompt"
  routes arg-profile_name valid -c 'profile_name="x"' "$prompt"
  routes arg-m valid -m o3 "$prompt"
  routes arg-prompt-mentions valid "use -p and --oss carefully"
  routes arg-after-dashes valid -- --profile x
  routes arg-after-dashes-oss valid --ephemeral -- --oss
  # Round 3: a first segment not in the list, and -C (not -c). The -C value
  # is a directory whose first dotted segment is a listed key, so reading -C
  # as -c would refuse it.
  routes arg-model_providers_x valid -c 'model_providers_x=1' "$prompt"
  routes arg-profiles_x valid -c 'profiles_x=1' "$prompt"
  routes arg-capital-C valid -C profiles.d "$prompt"
  local line rest parts n=0
  while IFS= read -r line; do
    rest="${line#*|}"
    parts=()
    IFS=$'\t' read -r -a parts <<<"$rest"
    n=$((n + 1))
    routes "arg-round3-after-dashes-$n" valid --ephemeral -- "${parts[@]}"
  done <<<"$(round3_args)"
}
mkdir -p "$RC_CWD/profiles.d"
routed_args

# --- round 4: the inherited proxy environments (e1)-(e5) ------------------------
proxy_envs() {
  local e
  for e in $RC_PROXY_ENVS; do
    PENV="$e"
    routes "env-$e" valid --ephemeral "$prompt"
  done
  PENV=e1
}
proxy_envs
# proxy_env_routes <e>: one environment, as a mutant assertion.
proxy_env_routes() {
  PENV="$1"
  routes "env-$1" valid --ephemeral "$prompt"
  PENV=e1
}

# --- the Codex adapter ignores Claude routing state ---------------------------
rc_env_reset
rc_codex_config valid
rc_proxy_env e1
rc_env_set "ANTHROPIC_BASE_URL=http://127.0.0.1:9/elsewhere"
echo '{"env": {"ANTHROPIC_BASE_URL": "http://x"}}' >"$RC/cfg/settings.json"
rc_direct "$codex" exec x
rc_run codex -- "$codex" exec x
[ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S702/claude-state — the Codex adapter refused over Claude settings or ANTHROPIC_BASE_URL: $rc_err"
# Round 4: exactly NO_PROXY and no_proxy differ; the inherited
# ANTHROPIC_BASE_URL arrives unchanged.
[ "$(rc_env_diff)" = "$(rc_expected_loopback_diff)" ] || fail "S702/claude-state — the environment does not differ in exactly NO_PROXY and no_proxy: $(rc_env_diff)"
rm -f "$RC/cfg/settings.json"
rc_env_reset

# --- round 5: the Codex .env (Architect report 9) --------------------------------
# dotenv_setup <variant>: the valid config, inherited environment e1, and the
# .env of the variant in the place it names; sets DOTENV_DIR (the directory
# holding the .env under test) and DOTENV_WORD (what the message must name
# besides .env: the key, or that the file cannot be read).
#   x1-x4, xc1, xc2  the .env in the fixture CODEX_HOME
#   x5               CODEX_HOME elsewhere (valid config, the x1 .env), none
#                    in $HOME/.codex
#   x5-default       CODEX_HOME unset: the valid config and the x1 .env in
#                    $HOME/.codex
#   xc3              no .env
#   xc4              CODEX_HOME the fixture (valid config, no .env), the x1
#                    .env only in $HOME/.codex
dotenv_setup() {
  rc_env_reset
  rc_proxy_env e1
  rc_dotenv_clear
  rc_codex_config valid
  DOTENV_DIR="$RC/codexhome"
  DOTENV_WORD=NO_PROXY
  case "$1" in
    x1|x3) rc_codex_dotenv "$1" ;;
    x2) rc_codex_dotenv x2; DOTENV_WORD=no_proxy ;;
    x4) rc_codex_dotenv x4; DOTENV_WORD="cannot be read" ;;
    x5)
      DOTENV_DIR="$RC/elsewhere"
      cp "$RC/codexhome/config.toml" "$DOTENV_DIR/config.toml"
      rc_codex_dotenv x1 "$DOTENV_DIR"
      rc_env_set "CODEX_HOME=$DOTENV_DIR" ;;
    x5-default)
      DOTENV_DIR="$RC/home/.codex"
      mkdir -p "$DOTENV_DIR"
      cp "$RC/codexhome/config.toml" "$DOTENV_DIR/config.toml"
      rc_codex_dotenv x1 "$DOTENV_DIR"
      rc_env_del CODEX_HOME ;;
    xc1|xc2) rc_codex_dotenv "$1" ;;
    xc3) ;;
    xc4) mkdir -p "$RC/home/.codex"; rc_codex_dotenv x1 "$RC/home/.codex" ;;
    *) echo "dotenv_setup: unknown variant $1" >&2; return 1 ;;
  esac
}

# refused_dotenv <variant>: exit 4, no child, no probe, stdout empty, a
# message naming .env and DOTENV_WORD and never the value; the directory
# holding the .env and config.toml unchanged.
refused_dotenv() {
  local label="S702/dotenv/$1" h1
  dotenv_setup "$1"
  if [ "$1" = x4 ] && [ -r "$RC/codexhome/.env" ]; then
    fail "$label — the mode-000 fixture .env is still readable (running as root?), so this case cannot show an unreadable file"
    rc_dotenv_clear
    return
  fi
  h1="$(rc_tree_hash "$DOTENV_DIR")"
  rc_run codex -- "$codex" exec --ephemeral "$prompt"
  [ "$rc_status" = 4 ] || fail "$label — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started"
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran before the .env check refused"
  [ -z "$rc_out" ] || fail "$label — stdout is not empty: $rc_out"
  case "$rc_err" in *.env*) ;; *) fail "$label — the message does not name .env: $rc_err" ;; esac
  case "$rc_err" in *"$DOTENV_WORD"*) ;; *) fail "$label — the message does not name '$DOTENV_WORD': $rc_err" ;; esac
  case "$rc_err" in *"$TOK"*) fail "$label — the message prints the value: $rc_err" ;; esac
  [ "$h1" = "$(rc_tree_hash "$DOTENV_DIR")" ] || fail "$label — .env or config.toml was written"
  rc_dotenv_clear
}

# routed_dotenv <variant>: routes as the valid config does (the same arguments
# and the round-4 environment e1), one probe call, every .env unchanged.
routed_dotenv() {
  local label="S702/dotenv/$1" h1
  dotenv_setup "$1"
  h1="$(rc_tree_hash "$RC/codexhome" "$RC/home")"
  rc_direct "$codex" exec --ephemeral "$prompt"
  rc_run codex -- "$codex" exec --ephemeral "$prompt"
  if [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ]; then
    rc_args_file exec -c "$RC_CODEX_HEADER_OVERRIDE" --ephemeral "$prompt"
    cmp -s "$RC/expected.args" "$RC/child.args" \
      || fail "$label — arguments are not: exec, -c, the header override, then the original rest"
    [ "$(rc_env_diff)" = "$(rc_expected_loopback_diff)" ] \
      || fail "$label — the environment does not differ from a direct run in exactly NO_PROXY and no_proxy: $(rc_env_diff)"
    [ "$rc_probe_calls" = 1 ] || fail "$label — the probe ran $rc_probe_calls times, expected once"
  else
    fail "$label — not routed: exit $rc_status, started $rc_started, stderr: $rc_err"
  fi
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome" "$RC/home")" ] || fail "$label — a .env or config.toml was written"
  rc_dotenv_clear
}
for x in x1 x2 x3 x4 x5 x5-default; do refused_dotenv "$x"; done
for x in xc1 xc2 xc3 xc4; do routed_dotenv "$x"; done
rc_env_reset

# --- usage errors exit 2 in every mode ---------------------------------------
usage_case() { # <label> <wrapper args...>
  local label="$1"
  shift
  rc_run "$@"
  [ "$rc_status" = 2 ] || fail "S702/usage/$mode/$label — exit $rc_status, expected 2 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "S702/usage/$mode/$label — a child was started"
  [ "$rc_probe_calls" = 0 ] || fail "S702/usage/$mode/$label — the probe ran"
  grep -qi usage <<<"$rc_err" || fail "S702/usage/$mode/$label — no usage line on stderr: $rc_err"
}
usage_mode() { # <mode>
  mode="$1"
  rc_env_reset
  rc_codex_config valid
  : >"$RC/probe.exit"
  case "$mode" in
    yes-off) rc_answer yes; rc_env_set "SDG_MODEL_ROUTE=off" ;;
    yes-refusing) rc_answer yes; rc_codex_config openai; echo 7 >"$RC/probe.exit" ;;
    *) rc_answer "$mode" ;;
  esac
  usage_case first-claude codex -- "$RC/bin/claude" exec x
  usage_case first-codexx codex -- "$RC/bin/codexx" exec x
  usage_case first-true codex -- /usr/bin/true
  usage_case empty-command codex -- ''
  usage_case no-command codex --
  usage_case missing-dashes codex "$codex" exec x
  usage_case no-arguments
  usage_case unknown-runtime gemini -- "$codex" exec x
  usage_case version codex -- "$codex" --version
  usage_case codex-alone codex -- "$codex"
  usage_case alias-e codex -- "$codex" e x
  usage_case option-before-exec codex -- "$codex" -c k=v exec x
  usage_case profile-before-exec codex -- "$codex" -p x exec x
  usage_case capital-exec codex -- "$codex" Exec x
  usage_case exec2 codex -- "$codex" exec2 x
  usage_case claude-first-codex claude -- "$codex" -p x
  usage_case claude-first-true claude -- /usr/bin/true
  rm -f "$RC/probe.exit"
  rc_answer yes
  rc_codex_config valid
}
for m in yes no pending absent yes-off yes-refusing; do usage_mode "$m"; done

# --- planted mutants: each must turn its assertion red --------------------------
EXEC_LINE='exec "$cmd" exec -c "$CODEX_HEADER_OVERRIDE" "$@"'
rc_kill "S702/kill/insert-before-exec" "$EXEC_LINE" 'exec "$cmd" -c "$CODEX_HEADER_OVERRIDE" exec "$@"' routes valid valid x
rc_kill "S702/kill/append-at-end" "$EXEC_LINE" 'exec "$cmd" exec "$@" -c "$CODEX_HEADER_OVERRIDE"' routes valid valid x
rc_kill "S702/kill/whole-file-grep-http_headers/e" \
  'provider_table = get(data, "model_providers", "caveman")' \
  'provider_table = get(data, "model_providers", "caveman")
if "http_headers" in open(config).read():
    stop("%s has http_headers" % named)' routes e header-other x
rc_kill "S702/kill/comment-blind-provider" \
  'provider, source = data.get("model_provider"), "the top-level model_provider"' \
  'provider, source = (re.findall(r"model_provider = .(\w+)", open(config).read()) or [None])[0], "the top-level model_provider"' \
  refused_config comment caveman
rc_kill "S702/kill/table-blind-provider" \
  'provider, source = data.get("model_provider"), "the top-level model_provider"' \
  'provider, source = (re.findall(r"model_provider = .(\w+)", open(config).read()) or [None])[-1], "the top-level model_provider"' \
  routes h profile x
rc_kill "S702/kill/top-level-only-provider" \
  'if selected is not None and "model_provider" in selected:' 'if False:' refused_config profile-direct direct caveman
rc_kill "S702/kill/top-level-only-provider/j" \
  'if selected is not None and "model_provider" in selected:' 'if False:' routes j profile-cv x
rc_kill "S702/kill/profile-ignored-when-table-missing" \
  '    if not isinstance(selected, dict):' '    if False:' refused_config profile-missing missing profile
rc_kill "S702/kill/inline-tables-unresolved" \
  'provider_table = get(data, "model_providers", "caveman")' \
  'provider_table = get(data, "model_providers", "caveman")
provider_table = None if isinstance(provider_table, Inline) or isinstance(get(data, "model_providers"), Inline) else provider_table' \
  refused_config inline-provider http_headers
rc_kill "S702/kill/inline-tables-unresolved/p" \
  'provider_table = get(data, "model_providers", "caveman")' \
  'provider_table = get(data, "model_providers", "caveman")
provider_table = None if isinstance(provider_table, Inline) else provider_table' \
  refused_config providers-table http_headers
rc_kill "S702/kill/profile-inline-unresolved" \
  '    selected = get(data, "profiles", profile) if isinstance(profile, str) else None' \
  '    selected = get(data, "profiles", profile) if isinstance(profile, str) else None
    selected = {} if isinstance(get(data, "profiles"), Inline) else selected' \
  refused_config profile-inline profile caveman
rc_kill "S702/kill/sub-table-missed" \
  'if isinstance(provider_table, dict) and key in provider_table:' 'if isinstance(provider_table, dict) and key in provider_table and not type(provider_table[key]) is dict:' \
  refused_config header-subtable http_headers
rc_kill "S702/kill/env_http_headers-unchecked" \
  'for key in ("http_headers", "env_http_headers"):' 'for key in ("http_headers",):' refused_config header-env env_http_headers
rc_kill "S702/kill/skip-on-parse-error" \
  'except TomlError as error:' 'except TomlError as error:
    sys.exit(0)' refused_config unparsable pars
rc_kill "S702/kill/overwrite-header" \
  'for key in ("http_headers", "env_http_headers"):' 'for key in ():' refused_config header http_headers
rc_kill "S702/kill/no-argument-check" 'while i < len(args):' 'while False:' refused_arg --profile up --profile "$TOK"
rc_kill "S702/kill/no-equals-forms" \
  '        name, eq, value = arg.partition("=")' '        name, eq, value = arg, "", ""' \
  refused_arg --profile up "--profile=$TOK"
rc_kill "S702/kill/no-equals-forms/c" \
  '(value[1:] if value.startswith("=") else value)' 'value' \
  refused_arg model_provider up "-c=model_provider=$TOK"
rc_kill "S702/kill/not-stopping-at-dashes" \
  '    if arg == "--":
        break' '    if arg == "--":
        pass' routes after-dashes valid -- --profile x
FIRST_SEGMENT_MATCH='        if first_segment(value) in keys:'
rc_kill "S702/kill/substring-key-match" "$FIRST_SEGMENT_MATCH" \
  '        if any(k in ".".join(segments(value)) for k in keys):' \
  routes profile_name valid -c 'profile_name="x"' x
rc_kill "S702/kill/untrimmed-key" \
  '    return [part.strip().strip("\"\x27").strip() for part in key.split(".")]' '    return key.split(".")' \
  refused_arg model_provider up -c " model_provider = \"$TOK\""
rc_kill "S702/kill/untrimmed-key/quoted-segment" \
  '    return [part.strip().strip("\"\x27").strip() for part in key.split(".")]' '    return key.split(".")' \
  refused_arg -c,profiles up -c " \"profiles\" .x.model_provider=\"$TOK\""
# Round 3 (Architect report 7).
rc_kill "S702/kill/text-prefix-instead-of-first-segment" "$FIRST_SEGMENT_MATCH" \
  '        if any(".".join(segments(value)).startswith(k) for k in keys):' \
  routes model_providers_x valid -c 'model_providers_x=1' x
ATTACHED='    elif arg[:2] in names:'
rc_kill "S702/kill/attached-forms-not-parsed/p" "$ATTACHED" '    elif arg in names:' refused_arg -p up "-p$TOK"
rc_kill "S702/kill/attached-forms-not-parsed/c" "$ATTACHED" '    elif arg in names:' \
  refused_arg -c,model_provider up "-cmodel_provider=\"$TOK\""
rc_kill "S702/kill/attached-match-case-insensitive" "$ATTACHED" '    elif arg[:2].lower() in names:' \
  routes capital-C valid -C profiles.d x
rc_kill "S702/kill/ignore-user-config-dropped" '
--ignore-user-config
' '
' refused_arg --ignore-user-config up --ignore-user-config
rc_kill "S702/kill/local-provider-dropped" '
--local-provider
' '
' refused_arg --local-provider up --local-provider "$TOK"
rc_kill "S702/kill/openai_base_url-dropped" '
-c|--config openai_base_url
' '
' refused_arg -c,openai_base_url up -c "openai_base_url=\"http://$TOK\""
rc_kill "S702/kill/chatgpt_base_url-dropped" "
-c|--config chatgpt_base_url'" "'" refused_arg -c,chatgpt_base_url up -c "chatgpt_base_url=\"http://$TOK\""
rc_kill "S702/kill/unknown-option-value-skipped" '    name, value = option_of(arg, refusing)' \
  '    if arg.startswith("-") and "=" not in arg and option_of(arg, refusing | config_options)[0] is None:
        i += 2
        continue
    name, value = option_of(arg, refusing)' refused_arg --oss up -o --oss
rc_kill "S702/kill/value-in-message" \
  '% (name, ".".join(segments(value))))' '% (name, value))' \
  refused_arg model_provider up -c "model_provider=\"$TOK\""
rc_kill "S702/kill/argument-check-after-probe" \
  '  check_codex routed "$@"' '  "${SDG_ROUTE_PROBE:-curl}" -s -o /dev/null "$PROXY_ORIGIN/" >/dev/null 2>&1 || exit 3
  check_codex routed "$@"' refused_arg --oss down --oss
rc_kill "S702/kill/usage-check-only-when-routing" \
  '  [ "${2:-}" = exec ] || usage' '  :' usage_mode no
rc_kill "S702/kill/exec-prefix-or-alias" \
  '  [ "${2:-}" = exec ] || usage' '  case "${2:-}" in e|exec*) ;; *) usage ;; esac' usage_mode yes
# Round 4 (Architect report 8): the loopback on a routed Codex child.
LB_NP='NO_PROXY="${NO_PROXY:+$NO_PROXY,}$LOOPBACK_NO_PROXY"'
LB_LNP='no_proxy="${no_proxy:+$no_proxy,}$LOOPBACK_NO_PROXY"'
rc_kill "S702/kill/NO_PROXY-not-added-for-Codex" "$LB_NP" ':' proxy_env_routes e1
rc_kill "S702/kill/no_proxy-not-added-for-Codex" "$LB_LNP" ':' proxy_env_routes e1
rc_kill "S702/kill/NO_PROXY-overwritten" "$LB_NP" 'NO_PROXY="$LOOPBACK_NO_PROXY"' proxy_env_routes e3
rc_kill "S702/kill/no_proxy-overwritten" "$LB_LNP" 'no_proxy="$LOOPBACK_NO_PROXY"' proxy_env_routes e2
rc_kill "S702/kill/no_proxy-from-NO_PROXY" "$LB_LNP" 'no_proxy="$NO_PROXY"' proxy_env_routes e2
rc_kill "S702/kill/leading-comma-on-empty" "$LB_NP" 'NO_PROXY="${NO_PROXY+$NO_PROXY,}$LOOPBACK_NO_PROXY"' proxy_env_routes e4
rc_kill "S702/kill/extra-variable-custom-headers" "$EXEC_LINE" \
  'ANTHROPIC_CUSTOM_HEADERS="$TRANSFORM_HEADER"; export ANTHROPIC_CUSTOM_HEADERS; '"$EXEC_LINE" proxy_env_routes e1
rc_kill "S702/kill/all-five-Claude-additions" "$EXEC_LINE" \
  'export ANTHROPIC_BASE_URL="$CLAUDE_ROUTE_URL" _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1 ANTHROPIC_CUSTOM_HEADERS="$TRANSFORM_HEADER"; '"$EXEC_LINE" proxy_env_routes e1
# Round 5 (Architect report 9): the Codex .env check.
DOTENV_KEYS="CODEX_CHILD_VARS='NO_PROXY no_proxy'"
DOTENV_PATH='dotenv="${CODEX_HOME:-$HOME/.codex}/.env"'
DOTENV_EXISTS='if not os.path.lexists(path):'
DOTENV_RE='assignment = re.compile(rb"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.]*)\s*=")'
rc_kill "S702/kill/dotenv-uppercase-key-only" "$DOTENV_KEYS" "CODEX_CHILD_VARS='NO_PROXY'" refused_dotenv x2
rc_kill "S702/kill/dotenv-lowercase-key-only" "$DOTENV_KEYS" "CODEX_CHILD_VARS='no_proxy'" refused_dotenv x1
rc_kill "S702/kill/dotenv-HOME-instead-of-CODEX_HOME" "$DOTENV_PATH" 'dotenv="$HOME/.codex/.env"' refused_dotenv x5
rc_kill "S702/kill/dotenv-HOME-instead-of-CODEX_HOME/xc4" "$DOTENV_PATH" 'dotenv="$HOME/.codex/.env"' routed_dotenv xc4
for x in x1 x3 x5; do
  rc_kill "S702/kill/dotenv-value-in-message/$x" '% (path, key))' '% (path, line.decode("utf-8", "replace")))' refused_dotenv "$x"
done
rc_kill "S702/kill/dotenv-export-form-missed" '(?:export\s+)?' '' refused_dotenv x3
rc_kill "S702/kill/dotenv-spaces-around-equals-missed" '([A-Za-z_][A-Za-z0-9_.]*)\s*=' '([A-Za-z_][A-Za-z0-9_.]*)=' refused_dotenv x3
rc_kill "S702/kill/dotenv-empty-value-passed" "$DOTENV_RE" \
  'assignment = re.compile(rb"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*\S")' refused_dotenv x2
rc_kill "S702/kill/dotenv-unreadable-as-absent" "$DOTENV_EXISTS" 'if not os.access(path, os.R_OK):' refused_dotenv x4
rc_kill "S702/kill/dotenv-first-line-only" 'for line in lines:' 'for line in lines[:1]:' refused_dotenv x1
rc_kill "S702/kill/dotenv-comment-line-counted" 'rb"\s*(?:export' 'rb"[\s#]*(?:export' routed_dotenv xc2
rc_kill "S702/kill/dotenv-any-proxy-key" "$DOTENV_KEYS" \
  "CODEX_CHILD_VARS='NO_PROXY no_proxy HTTP_PROXY http_proxy HTTPS_PROXY https_proxy'" routed_dotenv xc1
rc_kill "S702/kill/dotenv-missing-file-refused" "$DOTENV_EXISTS" 'if False:' routed_dotenv xc3
rc_kill "S702/kill/usage-after-checks" \
  '[ "$#" -ge 3 ] || usage' '[ "${1:-}" = codex ] && grep -q openai "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null && exit 4
[ "$#" -ge 3 ] || usage' usage_mode yes-refusing

test_done
