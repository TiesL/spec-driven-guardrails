#!/usr/bin/env bash
# S11 — Destructive commands are blocked.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
if [ ! -x "$guard" ]; then
  fail "S11 — hooks/git-guardrails is missing or not executable"
  test_done
fi

workdir="$(fresh_project workdir)"

# Runs the command past the guard, with the same JSON shape that Claude Code
# delivers on stdin. Echoes the exit status: 2 means blocked.
through_guard() {
  local command="$1" dir="${2:-$workdir}" extra_path="${3:-}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$dir" "$(printf '%s' "$command" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | PATH="${extra_path:+$extra_path:}$PATH" "$guard" >/dev/null 2>&1
  echo $?
}

blocked() {
  local description="$1" command="$2"
  if [ "$(through_guard "$command")" != "2" ]; then
    fail "S11 — not blocked: $description ($command)"
  fi
}

allowed() {
  local description="$1" command="$2" extra_path="${3:-}"
  if [ "$(through_guard "$command" "$workdir" "$extra_path")" = "2" ]; then
    fail "S11 — wrongly blocked: $description ($command)"
  fi
}

blocked "reset --hard"          "git reset --hard"
blocked "reset --hard HEAD~1"   "git reset --hard HEAD~1"
blocked "clean -fd"             "git clean -fd"
blocked "clean -f"              "git clean -f"
blocked "clean --force"         "git clean --force"
blocked "branch -D"             "git branch -D feature/old"
blocked "checkout ."            "git checkout ."
blocked "checkout -- ."         "git checkout -- ."
blocked "restore ."             "git restore ."
blocked "in a chain"            "git add . && git reset --hard"
blocked "branch --delete --force" "git branch --delete --force oud"
blocked "restore ./."            "git restore ./."
blocked "checkout ./"            "git checkout ./"

# An environment variable before the command belongs to the invocation, not to
# another program. Without that step, every var prefix bypasses the entire guard - all
# rules at once, not just this one.
blocked "with env prefix"         "GIT_TRACE=1 git reset --hard"
blocked "with two env prefixes"  "FOO=bar GIT_TRACE=1 git clean -fd"

# What must NOT be blocked. A false positive blocks work in four
# projects at once, so this weighs heavier than a missed case.
allowed "reset without --hard"    "git reset HEAD~1"
allowed "reset --soft"           "git reset --soft HEAD~1"
allowed "clean -n (dry run)"     "git clean -n"
allowed "branch -d (safe)"     "git branch -d feature/done"
allowed "branch without flag"     "git branch"
allowed "checkout of a branch" "git checkout main"
allowed "checkout -b"            "git checkout -b feature/1-new" "$(path_without_gh)"
allowed "restore of a single file" "git restore src/app.ts"
allowed "checkout of a single file" "git checkout -- src/app.ts"
allowed "status"                 "git status"
allowed "not a git command"      "rm -rf build"
allowed "the text inside a string" "echo 'never use git reset --hard'"

# Only segments that start with `git` are evaluated. Without that requirement,
# every command whose second word happens to be a git subcommand would be
# blocked — and those are ordinary, everyday commands.
allowed "make clean with -f"      "make clean -f Makefile"
allowed "npm run clean"          "npm run clean -- --force"
allowed "docker restore"         "docker restore ."

# Long options are not short-flag clusters. `--exclude=foo` contains an `f` and
# `--set-upstream-to=origin/DEV` a `D`, but neither is destructive.
# These are everyday commands; blocking them is the worst outcome.
allowed "clean -n with --exclude"  "git clean -n --exclude=foo"
allowed "clean --dry-run"         "git clean --dry-run"

# The rule is that a long option never counts as a short-flag cluster. The two
# cases above do not touch that rule: "--exclude" and "--set-upstream-to"
# do not themselves contain an f or D, only their value. These two do. Whether git
# knows these options today is not the point — git gains more with every version,
# and the guard should not suddenly start reacting to that.
allowed "long option containing an f"  "git clean --dry-run --filter=build"
allowed "long option containing a D"  "git branch --list --DEV-only"
allowed "branch --set-upstream-to" "git branch --set-upstream-to=origin/DEV"
allowed "branch --format with D"   "git branch --format=%(refname:short)-DEV"
allowed "git with -C"              "git -C /path status"
allowed "env prefix without danger" "GIT_TRACE=1 git status"

# The deliberate escape hatch. A guard without an escape hatch eventually gets
# bypassed by editing the script; so it must exist and be loud.
# The escape hatch must work the way the block message prescribes: as a prefix
# in the command text. A command that has not yet started cannot by definition
# affect the guard's own environment, so testing only the guard's own
# environment would never hit the documented form.
from_error="$SANDBOX/escape.txt"
printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git reset --hard"}}' \
  "$workdir" | "$guard" >/dev/null 2>"$from_error"
from_status=$?

[ "$from_status" -ne 2 ] || fail "S11 — the escape hatch does not work; the command remained blocked"
[ -s "$from_error" ] || fail "S11 — the escape hatch reports nothing; a silent escape hatch is a disabled guard"
grep -qi 'warning' "$from_error" || {
  fail "S11 — the escape hatch message is not recognizable as a warning"
  cat "$from_error" >&2
}

test_done
