#!/usr/bin/env bash
# S702 — A routed Codex child gets the header after `exec`; mismatched configs refuse; usage errors exit 2 in every mode (#707; AC3, AC4 usage half)
# Covers: F75
#
# Seam: route-child.sh as a process with a stub named `codex`, a fixture
# CODEX_HOME/config.toml per variant (hashed before and after), the probe stub.

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

# --- routed variants ----------------------------------------------------------
for v in valid header-other profile; do
  rc_codex_config "$v"
  h1="$(rc_tree_hash "$RC/codexhome")"
  rc_direct "$codex" exec --ephemeral "$prompt"
  rc_run codex -- "$codex" exec --ephemeral "$prompt"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "S702/$v — not routed: exit $rc_status, started $rc_started, stderr: $rc_err"
  rc_args_file exec -c "$RC_CODEX_HEADER_OVERRIDE" --ephemeral "$prompt"
  cmp -s "$RC/expected.args" "$RC/child.args" \
    || fail "S702/$v — arguments are not: exec, -c, the header override, then the original rest"
  [ -z "$(rc_env_diff)" ] || fail "S702/$v — the Codex adapter changed the environment: $(rc_env_diff)"
  [ "$rc_probe_calls" = 1 ] || fail "S702/$v — the probe ran $rc_probe_calls times, expected once"
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "S702/$v — config.toml was written"
done

# --- refusing variants --------------------------------------------------------
check_refusal() { # <variant> <word that must appear in the message>
  local v="$1" word="$2" h1
  rc_codex_config "$v"
  h1="$(rc_tree_hash "$RC/codexhome")"
  rc_run codex -- "$codex" exec --ephemeral "$prompt"
  [ "$rc_status" = 4 ] || fail "S702/$v — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "S702/$v — the child was started"
  case "$rc_err" in *config.toml*) ;; *) fail "S702/$v — the message does not name config.toml: $rc_err" ;; esac
  grep -qi -- "$word" <<<"$rc_err" || fail "S702/$v — the message does not give the cause ('$word'): $rc_err"
  [ "$rc_probe_calls" = 0 ] || fail "S702/$v — the probe ran before the config check refused"
  [ "$h1" = "$(rc_tree_hash "$RC/codexhome")" ] || fail "S702/$v — config.toml was written"
}
check_refusal openai caveman
check_refusal nokey caveman
check_refusal comment caveman
check_refusal header http_headers
check_refusal unparsable pars
check_refusal missing caveman
rc_codex_config valid

# --- the Codex adapter ignores Claude routing state ---------------------------
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
for mode in yes no pending absent yes-off yes-refusing; do
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
  usage_case capital-exec codex -- "$codex" Exec x
  usage_case exec2 codex -- "$codex" exec2 x
  usage_case claude-first-codex claude -- "$codex" -p x
  usage_case claude-first-true claude -- /usr/bin/true
done
: >"$RC/probe.exit"

test_done
