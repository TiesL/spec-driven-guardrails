#!/usr/bin/env bash
# S707 — The checked settings locations are exactly the documented list (#707; AC8)
# Covers: F75
#
# Seam: one placement of a routing settings file per run through the wrapper's
# process Interface; SDG_ROUTE_MANAGED_SETTINGS as the only way to fake the
# managed path; a fake `uname` first on PATH for the platform.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT
rc_init

[ -x "$RC_ROUTE" ] || { fail "S707 — route-child.sh is missing or not executable"; test_done; }

claude="$RC/bin/claude"
route_json='{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:9/dead"}}'
clean_json='{"permissions":{}}'

place() { # <file>: writes the routing fixture there
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$route_json" >"$1"
}

expect_refused() { # <label> <file>
  rc_run claude -- "$claude" -p x
  [ "$rc_status" = 4 ] && [ "$rc_started" = 0 ] || fail "$1 — not refused: exit $rc_status, started $rc_started"
  case "$rc_err" in *"$2"*) ;; *) fail "$1 — the message does not name $2: $rc_err" ;; esac
}
expect_started() { # <label>
  rc_direct "$claude" -p x
  rc_run claude -- "$claude" -p x
  [ "$rc_status" = 0 ] && [ "$rc_started" = 1 ] || fail "$1 — refused: exit $rc_status, $rc_err"
  [ "$(rc_env_diff)" = "$(rc_expected_claude_diff)" ] || fail "$1 — not routed as in S701"
}

# --- the seven listed placements -------------------------------------------------
listed=(
  "cfg|$RC/cfg/settings.json"
  "home|$RC/home/.claude/settings.json"
  "cwd|$RC_CWD/.claude/settings.json"
  "cwd|$RC_CWD/.claude/settings.local.json"
  "top|$RC_TOP/.claude/settings.json"
  "top|$RC_TOP/.claude/settings.local.json"
  "managed|$RC/managed/managed-settings.json"
)
for entry in "${listed[@]}"; do
  kind="${entry%%|*}" f="${entry#*|}"
  rc_env_reset
  [ "$kind" = home ] && rc_env_del CLAUDE_CONFIG_DIR
  place "$f"
  expect_refused "S707/listed/${f#"$RC"/}" "$f"
  rm -f "$f"
done

# --- places that are not on the list ---------------------------------------------
unlisted=(
  "cfg-set|$RC/home/.claude/settings.json"
  "|$RC_TOP/sub/sibling/.claude/settings.json"
  "|$RC/.claude/settings.json"
  "|$RC_CWD/deeper/.claude/settings.json"
  "|$RC/home/.claude/settings.local.json"
  "|$RC_TOP/settings.json"
  "|$RC_CWD/settings.json"
)
for entry in "${unlisted[@]}"; do
  f="${entry#*|}"
  rc_env_reset
  place "$f"
  expect_started "S707/unlisted/${f#"$RC"/}"
  rm -f "$f"
done
# CLAUDE_CONFIG_DIR unset: the cfg directory is no longer the user location.
rc_env_reset
rc_env_del CLAUDE_CONFIG_DIR
place "$RC/cfg/settings.json"
expect_started "S707/unlisted/cfg-while-unset"
rm -f "$RC/cfg/settings.json"

# --- platform and the managed-path variable ----------------------------------------
fake_uname() { printf '#!/bin/sh\necho %s\n' "$1" >"$RC/bin/uname"; chmod +x "$RC/bin/uname"; }
for how in unset empty; do
  rc_env_reset
  fake_uname FreeBSD
  if [ "$how" = unset ]; then rc_env_del SDG_ROUTE_MANAGED_SETTINGS; else rc_env_set "SDG_ROUTE_MANAGED_SETTINGS="; fi
  rc_run claude -- "$claude" -p x
  label="S707/p-freebsd-$how"
  [ "$rc_status" = 4 ] && [ "$rc_started" = 0 ] || fail "$label — not refused: exit $rc_status, started $rc_started"
  grep -qE 'FreeBSD|uname' <<<"$rc_err" || fail "$label — the message does not name the platform: $rc_err"
  case "$rc_err" in *.json*) fail "$label — the message names a file: $rc_err" ;; esac
  [ "$rc_probe_calls" = 0 ] || fail "$label — the probe ran"
done
# p3: Darwin and Linux with the variable set to a clean file; the user file still refuses.
printf '%s\n' "$clean_json" >"$RC/managed/clean.json"
for os in Darwin Linux; do
  rc_env_reset
  fake_uname "$os"
  rc_env_set "SDG_ROUTE_MANAGED_SETTINGS=$RC/managed/clean.json"
  place "$RC/cfg/settings.json"
  expect_refused "S707/p3-$os" "$RC/cfg/settings.json"
  rm -f "$RC/cfg/settings.json"
done
rm -f "$RC/bin/uname"
# p4: the variable names a missing file: like a missing platform file.
rc_env_reset
rc_env_set "SDG_ROUTE_MANAGED_SETTINGS=$RC/managed/none/missing.json"
expect_started "S707/p4-missing"
# p5: the variable cannot skip another location, nor switch routing on.
rc_env_reset
rc_env_set "SDG_ROUTE_MANAGED_SETTINGS=$RC/managed/clean.json"
place "$RC_TOP/.claude/settings.json"
expect_refused "S707/p5-skip" "$RC_TOP/.claude/settings.json"
rc_answer no
rc_direct "$claude" -p x
rc_run claude -- "$claude" -p x
[ "$rc_started" = 1 ] && [ -z "$(rc_env_diff)" ] || fail "S707/p5-on — the managed variable switched routing on"
rc_answer yes
rm -f "$RC_TOP/.claude/settings.json"

test_done
