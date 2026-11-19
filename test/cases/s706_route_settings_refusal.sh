#!/usr/bin/env bash
# S706 — A settings file that routes the child, or cannot be read, refuses naming the file (#707; AC7)
# Covers: F75
#
# Seam: fixture settings files at each checked location plus `--settings`
# arguments, through the wrapper's process Interface. How the wrapper reads
# JSON is its own business; the test sees outcomes only.

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
mkdir -p "$RC_TOP/.claude" "$RC_CWD/.claude" "$RC/fx"
locations="$RC/cfg/settings.json
$RC_CWD/.claude/settings.json
$RC_CWD/.claude/settings.local.json
$RC_TOP/.claude/settings.json
$RC_TOP/.claude/settings.local.json
$RC/managed/managed-settings.json"

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
    name-elsewhere)
      printf '%s\n' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"ANTHROPIC_BASE_URL=x true"}]}]},' \
        '"permissions":{"deny":["Bash(export ANTHROPIC_BASE_URL=*)"]},"note":"env.ANTHROPIC_BASE_URL is not set"}' >"$1" ;;
  esac
}

refusing="route first-party empty-value truncated zero-byte whitespace array string env-string env-array env-null"
passing="no-key empty-object empty-env other-env name-elsewhere"

before="$(rc_tree_hash "$RC/cfg" "$RC_TOP" "$RC/managed")"
while IFS= read -r loc; do
  for v in $refusing unreadable; do
    if [ "$v" = unreadable ]; then
      if [ "$(id -u)" = 0 ]; then
        echo "S706 — skipped the unreadable case at $loc: running as root, mode 000 is readable" >&2
        continue
      fi
      write_variant "$loc" route
      chmod 000 "$loc"
    else
      write_variant "$loc" "$v"
    fi
    rc_run claude -- "$claude" -p x
    label="S706/$v/${loc#"$RC"/}"
    [ "$rc_status" = 4 ] || fail "$label — exit $rc_status, expected 4 (stderr: $rc_err)"
    [ "$rc_started" = 0 ] || fail "$label — the child was started"
    case "$rc_err" in *"$loc"*) ;; *) fail "$label — the message does not name the file: $rc_err" ;; esac
    [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
    chmod 644 "$loc" 2>/dev/null
    rm -f "$loc"
  done
  for v in $passing; do
    write_variant "$loc" "$v"
    rc_direct "$claude" -p x
    rc_run claude -- "$claude" -p x
    label="S706/$v/${loc#"$RC"/}"
    [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "$label — refused: exit $rc_status, $rc_err"
    [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "$label — not routed as in S701"
    rm -f "$loc"
  done
done <<<"$locations"
# Every location also passes when the file is missing (the loop removed them).
rc_run claude -- "$claude" -p x
[ "$rc_started" = 1 ] || fail "S706/missing — refused with no settings files: $rc_err"

# A refusing or passing fixture is never changed by the wrapper.
write_variant "$RC/cfg/settings.json" name-elsewhere
h1="$(rc_tree_hash "$RC/cfg")"
rc_run claude -- "$claude" -p x
[ "$h1" = "$(rc_tree_hash "$RC/cfg")" ] || fail "S706 — a passing settings file was changed"
write_variant "$RC/cfg/settings.json" truncated
h1="$(rc_tree_hash "$RC/cfg")"
rc_run claude -- "$claude" -p x
[ "$h1" = "$(rc_tree_hash "$RC/cfg")" ] || fail "S706 — a refusing settings file was repaired or rewritten"
rm -f "$RC/cfg/settings.json"

# --- (f) --settings arguments -------------------------------------------------
write_variant "$RC/fx/route.json" route
write_variant "$RC/fx/bad.json" truncated
write_variant "$RC/fx/clean.json" no-key
for form in separate equals; do
  for target in route bad missing; do
    f="$RC/fx/$target.json"
    if [ "$form" = separate ]; then rc_run claude -- "$claude" -p x --settings "$f"
    else rc_run claude -- "$claude" -p x "--settings=$f"; fi
    label="S706/f/$form/$target"
    [ "$rc_status" = 4 ] && [ "$rc_started" = 0 ] || fail "$label — not refused: exit $rc_status, started $rc_started"
    case "$rc_err" in *"$f"*) ;; *) fail "$label — the message does not name $f: $rc_err" ;; esac
    [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
  done
  if [ "$form" = separate ]; then set -- -p x --settings "$RC/fx/clean.json"
  else set -- -p x "--settings=$RC/fx/clean.json"; fi
  rc_direct "$claude" "$@"
  rc_run claude -- "$claude" "$@"
  [ "$rc_started" = 1 ] || fail "S706/f/$form/clean — refused: $rc_err"
  rc_args_equal_direct || fail "S706/f/$form/clean — the --settings argument was not passed through unchanged"
  [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "S706/f/$form/clean — not routed as in S701"
done
for inline in '{"env":{"ANTHROPIC_BASE_URL":"http://x"}}' '{"env":' ' {"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}'; do
  rc_run claude -- "$claude" -p x --settings "$inline"
  [ "$rc_status" = 4 ] && [ "$rc_started" = 0 ] || fail "S706/f/inline [$inline] — not refused: exit $rc_status"
  grep -q 'inline --settings' <<<"$rc_err" || fail "S706/f/inline [$inline] — the message does not say 'inline --settings': $rc_err"
done
rc_direct "$claude" -p x --settings '{"permissions":{}}'
rc_run claude -- "$claude" -p x --settings '{"permissions":{}}'
[ "$rc_started" = 1 ] || fail "S706/f/inline-clean — refused: $rc_err"
rc_args_equal_direct || fail "S706/f/inline-clean — arguments changed"

after="$(rc_tree_hash "$RC/cfg" "$RC_TOP" "$RC/managed")"
[ "$before" = "$after" ] || fail "S706 — the fixture tree differs from before (a file was left or written)"

test_done
