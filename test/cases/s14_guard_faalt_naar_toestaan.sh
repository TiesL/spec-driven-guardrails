#!/usr/bin/env bash
# S14 — The guard fails open (allows) when it is itself broken.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S14 — hooks/git-guardrails is missing"; test_klaar; }

project="$(vers_project werk)"
invoer='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git reset --hard"}}'

# Given: no jq and no python3 in PATH. A minimal bin directory with only the
# basic tools mimics a bare hook environment.
bin="$SANDBOX/minbin"
mkdir -p "$bin"
for t in bash sh sed grep cut tr git dirname basename cat head printf; do
  pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$bin/$t"
done

fout="$SANDBOX/stderr.txt"
printf '%s' "$invoer" | PATH="$bin" "$guard" >/dev/null 2>"$fout"
status=$?

# Without jq and python3 the guard may well block if it can still read the
# command — but it must never fall silent without saying anything.
if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
  fail "S14 — unexpected exit status $status without jq/python3"
fi

# Given: no usable tool at all to read the input.
kaal="$SANDBOX/kaal"
mkdir -p "$kaal"
for t in bash sh git; do
  pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$kaal/$t"
done

fout2="$SANDBOX/stderr2.txt"
printf '%s' "$invoer" | PATH="$kaal" "$guard" >/dev/null 2>"$fout2"
status2=$?

# Then: a loud warning appears, and the command is allowed.
[ "$status2" -ne 2 ] || fail "S14 — the guard blocked while it could not read the input"
[ -s "$fout2" ] || fail "S14 — no warning when the guard could not read the input"
grep -qi 'warning' "$fout2" || {
  fail "S14 — the message is not recognizable as a warning"
  cat "$fout2" >&2
}

# And with unreadable input (not valid JSON) the same: allow, do not guess.
printf 'dit is geen json' | "$guard" >/dev/null 2>/dev/null
[ $? -ne 2 ] || fail "S14 — the guard blocked on input that is not JSON"

# Empty input must not trip it up either.
printf '' | "$guard" >/dev/null 2>/dev/null
[ $? -ne 2 ] || fail "S14 — the guard blocked on empty input"

test_klaar
