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
# -c, the header override, then the original rest byte for byte; no
# environment change; one probe call; config.toml unchanged.
routes() {
  local label="$1" v="$2" h1
  shift 2
  rc_env_reset
  rc_codex_config "$v"
  h1="$(rc_tree_hash "$RC/codexhome")"
  rc_direct "$codex" exec "$@"
  rc_run codex -- "$codex" exec "$@"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "S702/$label — not routed: exit $rc_status, started $rc_started, stderr: $rc_err"; return; }
  rc_args_file exec -c "$RC_CODEX_HEADER_OVERRIDE" "$@"
  cmp -s "$RC/expected.args" "$RC/child.args" \
    || fail "S702/$label — arguments are not: exec, -c, the header override, then the original rest"
  [ -z "$(rc_env_diff)" ] || fail "S702/$label — the Codex adapter changed the environment: $(rc_env_diff)"
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

# refused_arg <name> <up|down> <args after exec...>: with the valid config,
# exit 4, no child, no probe, a message naming the argument <name> and not
# the value token.
refused_arg() {
  local name="$1" probe="$2" label
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
  case "$rc_err" in *"$name"*) ;; *) fail "$label — the message does not name '$name': $rc_err" ;; esac
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
}
routed_args

# --- the Codex adapter ignores Claude routing state ---------------------------
rc_env_reset
rc_codex_config valid
rc_env_set "ANTHROPIC_BASE_URL=http://127.0.0.1:9/elsewhere"
echo '{"env": {"ANTHROPIC_BASE_URL": "http://x"}}' >"$RC/cfg/settings.json"
rc_direct "$codex" exec x
rc_run codex -- "$codex" exec x
[ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S702/claude-state — the Codex adapter refused over Claude settings or ANTHROPIC_BASE_URL: $rc_err"
[ -z "$(rc_env_diff)" ] || fail "S702/claude-state — environment changed: $(rc_env_diff)"
rm -f "$RC/cfg/settings.json"
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
  'caveman = get(data, "model_providers", "caveman")' \
  'caveman = get(data, "model_providers", "caveman")
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
  'caveman = get(data, "model_providers", "caveman")' \
  'caveman = get(data, "model_providers", "caveman")
caveman = None if isinstance(caveman, Inline) or isinstance(get(data, "model_providers"), Inline) else caveman' \
  refused_config inline-provider http_headers
rc_kill "S702/kill/inline-tables-unresolved/p" \
  'caveman = get(data, "model_providers", "caveman")' \
  'caveman = get(data, "model_providers", "caveman")
caveman = None if isinstance(caveman, Inline) else caveman' \
  refused_config providers-table http_headers
rc_kill "S702/kill/profile-inline-unresolved" \
  '    selected = get(data, "profiles", profile) if isinstance(profile, str) else None' \
  '    selected = get(data, "profiles", profile) if isinstance(profile, str) else None
    selected = {} if isinstance(get(data, "profiles"), Inline) else selected' \
  refused_config profile-inline profile caveman
rc_kill "S702/kill/sub-table-missed" \
  'if isinstance(caveman, dict) and key in caveman:' 'if isinstance(caveman, dict) and key in caveman and not type(caveman[key]) is dict:' \
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
  'name, eq, inline = arg.partition("=") if arg.startswith("-") else (arg, "", "")' 'name, eq, inline = arg, "", ""' \
  refused_arg --profile up "--profile=$TOK"
rc_kill "S702/kill/no-equals-forms/c" \
  'name, eq, inline = arg.partition("=") if arg.startswith("-") else (arg, "", "")' 'name, eq, inline = arg, "", ""' \
  refused_arg model_provider up "-c=model_provider=$TOK"
rc_kill "S702/kill/not-stopping-at-dashes" \
  '    if arg == "--":
        break' '    if arg == "--":
        pass' routes after-dashes valid -- --profile x
rc_kill "S702/kill/substring-key-match" '    return key == pattern' '    return pattern in key' \
  routes profile_name valid -c 'profile_name="x"' x
rc_kill "S702/kill/untrimmed-key" '    return ".".join(' '    return key
    return ".".join(' refused_arg model_provider up -c " model_provider = \"$TOK\""
rc_kill "S702/kill/value-in-message" \
  'which would decide the route instead of the wrapper; remove it" % (name, key))' \
  'which would decide the route instead of the wrapper; remove it" % (name, value))' \
  refused_arg model_provider up -c "model_provider=\"$TOK\""
rc_kill "S702/kill/argument-check-after-probe" \
  '  check_codex routed "$@"' '  "${SDG_ROUTE_PROBE:-curl}" -s -o /dev/null "$PROXY_ORIGIN/" >/dev/null 2>&1 || exit 3
  check_codex routed "$@"' refused_arg --oss down --oss
rc_kill "S702/kill/usage-check-only-when-routing" \
  '  [ "${2:-}" = exec ] || usage' '  :' usage_mode no
rc_kill "S702/kill/exec-prefix-or-alias" \
  '  [ "${2:-}" = exec ] || usage' '  case "${2:-}" in e|exec*) ;; *) usage ;; esac' usage_mode yes
rc_kill "S702/kill/usage-after-checks" \
  '[ "$#" -ge 3 ] || usage' '[ "${1:-}" = codex ] && grep -q openai "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null && exit 4
[ "$#" -ge 3 ] || usage' usage_mode yes-refusing

test_done
