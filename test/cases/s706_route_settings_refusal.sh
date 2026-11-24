#!/usr/bin/env bash
# S706 — A settings file that sets a variable the wrapper adds, or cannot be read, refuses naming the file and the key (#707; AC7)
# Covers: F75
#
# Seam: fixture settings files at each checked location plus `--settings`
# arguments, through the wrapper's process Interface. How the wrapper reads
# JSON is its own business; the test sees outcomes only. The refused key set
# is taken from the variables a routed child shows as added (S701's
# environment diff), not from a list typed in here. Each assertion is a
# function, run against the real wrapper and then against planted mutants
# that must turn it red (rc_kill).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S706 — route-child.sh is missing or not executable"; test_done; }

claude="$RC/bin/claude"
TOK=tok-7f3a
mkdir -p "$RC_TOP/.claude" "$RC_CWD/.claude" "$RC/fx"
USER_FILE="$RC/cfg/settings.json"
CWD_LOCAL="$RC_CWD/.claude/settings.local.json"
MANAGED_FILE="$RC/managed/managed-settings.json"
locations="$USER_FILE
$RC_CWD/.claude/settings.json
$CWD_LOCAL
$RC_TOP/.claude/settings.json
$RC_TOP/.claude/settings.local.json
$MANAGED_FILE"

# write_variant <file> <variant>
write_variant() {
  case "$2" in
    route) printf '{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:9/dead"}}\n' >"$1" ;;
    first-party) printf '{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}\n' >"$1" ;;
    empty-value) printf '{"env":{"ANTHROPIC_BASE_URL":""}}\n' >"$1" ;;
    truncated) printf '{"env":{"ANTHROPIC_BASE_URL"' >"$1" ;;
    zero-byte) : >"$1" ;;
    whitespace) printf '  \n\t\n' >"$1" ;;
    array) printf '[]\n' >"$1" ;;
    string) printf '"x"\n' >"$1" ;;
    env-string) printf '{"env":"x"}\n' >"$1" ;;
    env-array) printf '{"env":[]}\n' >"$1" ;;
    env-null) printf '{"env":null}\n' >"$1" ;;
    no-key) printf '{"permissions":{"allow":["Bash(ls)"]}}\n' >"$1" ;;
    empty-object) printf '{}\n' >"$1" ;;
    empty-env) printf '{"env":{}}\n' >"$1" ;;
    other-env) printf '{"env":{"FOO":"1","ANTHROPIC_MODEL":"x"}}\n' >"$1" ;;
    key-as-value) printf '{"env":{"FOO":"NO_PROXY"}}\n' >"$1" ;;
    key-prefix) printf '{"env":{"ANTHROPIC_CUSTOM_HEADERS_X":"1"}}\n' >"$1" ;;
    key-suffix) printf '{"env":{"XNO_PROXY":"1"}}\n' >"$1" ;;
    name-elsewhere)
      printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"ANTHROPIC_BASE_URL=x ANTHROPIC_CUSTOM_HEADERS=y true"}]}]},' \
        '"permissions":{"deny":["Bash(export ANTHROPIC_BASE_URL=*)","Bash(export ANTHROPIC_CUSTOM_HEADERS=*)"]},"note":"env.ANTHROPIC_BASE_URL and env.ANTHROPIC_CUSTOM_HEADERS are not set"}' >"$1" ;;
  esac
}
refusing="route first-party empty-value truncated zero-byte whitespace array string env-string env-array env-null"
passing="no-key empty-object empty-env other-env key-as-value key-prefix key-suffix name-elsewhere"

# expect_refused <label> <file or "inline --settings"> [<key>] [wrapper command args...]
expect_refused() {
  local label="$1" where="$2" key="$3"
  shift 3
  [ "$#" -gt 0 ] || set -- -p x
  rc_run claude -- "$claude" "$@"
  [ "$rc_status" = 4 ] || fail "$label — exit $rc_status, expected 4 (stderr: $rc_err)"
  [ "$rc_started" = 0 ] || fail "$label — the child was started"
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
  case "$rc_err" in *"$where"*) ;; *) fail "$label — the message does not name '$where': $rc_err" ;; esac
  if [ -n "$key" ]; then
    grep -qE -- "(^|[^A-Za-z0-9_])$key([^A-Za-z0-9_]|\$)" <<<"$rc_err" || fail "$label — the message does not name the key $key: $rc_err"
  fi
  case "$rc_err" in *"$TOK"*) fail "$label — the message prints the value: $rc_err" ;; esac
}
# expect_routed <label> [command args...]
expect_routed() {
  local label="$1"
  shift
  [ "$#" -gt 0 ] || set -- -p x
  rc_direct "$claude" "$@"
  rc_run claude -- "$claude" "$@"
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || { fail "$label — refused: exit $rc_status, $rc_err"; return; }
  [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "$label — not routed as in S701"
  rc_args_equal_direct || fail "$label — the arguments were changed"
}

# --- (a)-(e) at every location ------------------------------------------------
refused_at() { # <file> <variant>
  local loc="$1" v="$2" key=""
  rc_env_reset
  if [ "$v" = unreadable ]; then
    write_variant "$loc" route
    chmod 000 "$loc"
  else
    write_variant "$loc" "$v"
  fi
  case "$v" in route|first-party|empty-value) key=ANTHROPIC_BASE_URL ;; esac
  expect_refused "S706/$v/${loc#"$RC"/}" "$loc" "$key"
  chmod 644 "$loc" 2>/dev/null
  rm -f "$loc"
}
routed_at() { # <file> <variant>
  rc_env_reset
  write_variant "$1" "$2"
  expect_routed "S706/$2/${1#"$RC"/}"
  rm -f "$1"
}
before="$(rc_tree_hash "$RC/cfg" "$RC_TOP" "$RC/managed")"
while IFS= read -r loc; do
  for v in $refusing; do refused_at "$loc" "$v"; done
  if [ "$(id -u)" = 0 ]; then
    echo "S706 — skipped the unreadable case at $loc: running as root, mode 000 is readable" >&2
  else
    refused_at "$loc" unreadable
  fi
  for v in $passing; do routed_at "$loc" "$v"; done
done <<<"$locations"
# Every location also passes when the file is missing (the loop removed them).
expect_routed "S706/missing"

# --- (a2) and (f2): the refused key set equals the added set --------------------
rc_env_reset
rc_direct "$claude" -p x
rc_run claude -- "$claude" -p x
ADDED="$(rc_added_names)"
added_five() {
  local names
  rc_env_reset
  rc_direct "$claude" -p x
  rc_run claude -- "$claude" -p x
  names="$(rc_added_names)"
  [ "$(rc_line_count "$names")" = 5 ] || fail "S706/added-set — a routed child shows $(rc_line_count "$names") added variables, expected exactly five: $(echo $names)"
}
added_five

# key_file <file> <key> <tok|empty|beside>
key_file() {
  case "$3" in
    tok) printf '{"env":{"%s":"%s"}}\n' "$2" "$TOK" >"$1" ;;
    empty) printf '{"env":{"%s":""}}\n' "$2" >"$1" ;;
    beside) printf '{"env":{"FOO":"1","%s":"%s"}}\n' "$2" "$TOK" >"$1" ;;
  esac
}
key_refused() { # <key> <user|cwd-local|managed|settings-arg> <tok|empty|beside>
  local key="$1" where="$2" form="$3" f
  rc_env_reset
  case "$where" in
    user) f="$USER_FILE" ;;
    cwd-local) f="$CWD_LOCAL" ;;
    managed) f="$MANAGED_FILE" ;;
    settings-arg) f="$RC/fx/key.json" ;;
  esac
  key_file "$f" "$key" "$form"
  if [ "$where" = settings-arg ]; then
    expect_refused "S706/a2/$key/$where/$form" "$f" "$key" -p x --settings "$f"
  else
    expect_refused "S706/a2/$key/$where/$form" "$f" "$key"
  fi
  rm -f "$f"
}
inline_key_refused() { # <key>
  rc_env_reset
  expect_refused "S706/f2/$1" "inline --settings" "$1" -p x --settings "{\"env\":{\"$1\":\"$TOK\"}}"
}
for key in $ADDED; do
  for where in user cwd-local managed settings-arg; do
    for form in tok empty beside; do key_refused "$key" "$where" "$form"; done
  done
  inline_key_refused "$key"
done
rc_env_reset
expect_routed "S706/f2/FOO" -p x --settings '{"env":{"FOO":"1"}}'

# A refusing or passing fixture is never changed by the wrapper.
write_variant "$USER_FILE" name-elsewhere
h1="$(rc_tree_hash "$RC/cfg")"
rc_run claude -- "$claude" -p x
[ "$h1" = "$(rc_tree_hash "$RC/cfg")" ] || fail "S706 — a passing settings file was changed"
write_variant "$USER_FILE" truncated
h1="$(rc_tree_hash "$RC/cfg")"
rc_run claude -- "$claude" -p x
[ "$h1" = "$(rc_tree_hash "$RC/cfg")" ] || fail "S706 — a refusing settings file was repaired or rewritten"
rm -f "$USER_FILE"

# --- (f) --settings arguments -------------------------------------------------
write_variant "$RC/fx/route.json" route
write_variant "$RC/fx/bad.json" truncated
write_variant "$RC/fx/clean.json" no-key
settings_arg() { # <separate|equals> <route|bad|missing|clean>
  local f="$RC/fx/$2.json"
  rc_env_reset
  if [ "$2" = clean ]; then
    if [ "$1" = separate ]; then expect_routed "S706/f/$1/clean" -p x --settings "$f"
    else expect_routed "S706/f/$1/clean" -p x "--settings=$f"; fi
    return
  fi
  if [ "$1" = separate ]; then expect_refused "S706/f/$1/$2" "$f" "" -p x --settings "$f"
  else expect_refused "S706/f/$1/$2" "$f" "" -p x "--settings=$f"; fi
}
for form in separate equals; do
  for target in route bad missing clean; do settings_arg "$form" "$target"; done
done
inline_refused() { # <json>
  rc_env_reset
  expect_refused "S706/f/inline [$1]" "inline --settings" "" -p x --settings "$1"
}
for inline in '{"env":{"ANTHROPIC_BASE_URL":"http://x"}}' '{"env":' ' {"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}'; do
  inline_refused "$inline"
done
rc_env_reset
expect_routed "S706/f/inline-clean" -p x --settings '{"permissions":{}}'

after="$(rc_tree_hash "$RC/cfg" "$RC_TOP" "$RC/managed")"
[ "$before" = "$after" ] || fail "S706 — the fixture tree differs from before (a file was left or written)"

# --- planted mutants: each must turn its assertion red --------------------------
KEYS_LINE='KEYS = sys.argv[1].split()'
KEY_IN='        for key in KEYS:
            if key in env:'
rc_kill "S706/kill/base-URL-only" "$KEYS_LINE" 'KEYS = ["ANTHROPIC_BASE_URL"]' key_refused ANTHROPIC_CUSTOM_HEADERS user tok
for key in $ADDED; do
  rc_kill "S706/kill/drop-$key" "$KEYS_LINE" "KEYS = [k for k in sys.argv[1].split() if k != \"$key\"]" key_refused "$key" user tok
done
rc_kill "S706/kill/substring-key-match" "$KEY_IN" '        for key in KEYS:
            if any(key in k for k in env):' routed_at "$USER_FILE" key-suffix
rc_kill "S706/kill/prefix-key-match" "$KEY_IN" '        for key in KEYS:
            if any(k.startswith(key) for k in env):' routed_at "$USER_FILE" key-prefix
rc_kill "S706/kill/first-party-value-allowed" "$KEY_IN" '        for key in KEYS:
            if key in env and env[key] != "https://api.anthropic.com":' refused_at "$USER_FILE" first-party
rc_kill "S706/kill/empty-value-allowed" "$KEY_IN" '        for key in KEYS:
            if key in env and env[key]:' refused_at "$USER_FILE" empty-value
rc_kill "S706/kill/empty-file-as-ok" '        return "is empty"' '        return None' refused_at "$USER_FILE" zero-byte
rc_kill "S706/kill/whitespace-file-as-ok" '        return "is empty"' '        return None if text else "is empty"' refused_at "$USER_FILE" whitespace
rc_kill "S706/kill/array-top-level-as-ok" '        return "is not a JSON object"' '        return None' refused_at "$USER_FILE" array
rc_kill "S706/kill/non-object-env-as-ok" '            return "has an env that is not an object"' '            return None' refused_at "$USER_FILE" env-null
rc_kill "S706/kill/empty-object-refused" '    if not isinstance(data, dict):' '    if not isinstance(data, dict) or not data:' routed_at "$USER_FILE" empty-object
rc_kill "S706/kill/skip-on-unparsable" '        return "is not valid JSON"' '        return None' refused_at "$USER_FILE" truncated
if [ "$(id -u)" != 0 ]; then
  rc_kill "S706/kill/skip-on-unreadable" '            print("%s cannot be read (%s)" % (name, reason))
            sys.exit(1)' '            continue' refused_at "$USER_FILE" unreadable
fi
rc_kill "S706/kill/text-grep" '    problem = verdict(text)' \
  '    problem = ("sets a variable" if any(k in text for k in KEYS) else None) or verdict(text)' routed_at "$USER_FILE" name-elsewhere
rc_kill "S706/kill/user-file-only/cwd" '      cwd) specs+=(optional "$PWD/$file") ;;' '      cwd) ;;' refused_at "$CWD_LOCAL" route
rc_kill "S706/kill/user-file-only/top" '      top) specs+=(optional "$top/$file") ;;' '      top) ;;' refused_at "$RC_TOP/.claude/settings.json" route
rc_kill "S706/kill/user-file-only/managed" '      managed) specs+=(optional "$managed_path") ;;' '      managed) ;;' refused_at "$MANAGED_FILE" route
rc_kill "S706/kill/warn-and-start" '    1) refuse "$problem. Remove the setting there, or run with SDG_MODEL_ROUTE=off." ;;' \
  '    1) echo "$problem" >&2 ;;' refused_at "$USER_FILE" route
rc_kill "S706/kill/file-name-missing" '        print("%s %s" % (name, problem))' '        print("a settings file %s" % problem)' refused_at "$USER_FILE" route
rc_kill "S706/kill/key-missing" '"sets env.%s, which outranks the value the wrapper gives the child" % key' \
  '"sets a variable the wrapper adds"' key_refused NO_PROXY user tok
rc_kill "S706/kill/value-in-message" '"sets env.%s, which outranks the value the wrapper gives the child" % key' \
  '"sets env.%s, which outranks the value the wrapper gives the child" % (key + "=" + str(env[key]))' key_refused no_proxy user tok
rc_kill "S706/kill/settings-equals-form-missed" '"$file="*) specs+=(argument "${arg#"$file="}") ;;' '"$file="*) ;;' settings_arg equals route
rc_kill "S706/kill/inline-form-missed" '    if kind == "argument" and value.lstrip().startswith("{"):' '    if False:' inline_refused '{"env":{"ANTHROPIC_BASE_URL":"http://x"}}'
rc_kill "S706/kill/sixth-child-variable" 'export $CLAUDE_CHILD_VARS
exec "$@"' 'export $CLAUDE_CHILD_VARS
export HTTP_PROXY=
exec "$@"' added_five

test_done
