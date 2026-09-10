#!/usr/bin/env bash
# S11 — Destructive commands are blocked.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
if [ ! -x "$guard" ]; then
  fail "S11 — hooks/git-guardrails is missing or not executable"
  test_klaar
fi

werkmap="$(vers_project werkmap)"

# Runs the command past the guard, with the same JSON shape that Claude Code
# delivers on stdin. Echoes the exit status: 2 means blocked.
langs_guard() {
  local commando="$1" map="${2:-$werkmap}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$map" "$(printf '%s' "$commando" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

geblokkeerd() {
  local omschrijving="$1" commando="$2"
  if [ "$(langs_guard "$commando")" != "2" ]; then
    fail "S11 — not blocked: $omschrijving ($commando)"
  fi
}

toegestaan() {
  local omschrijving="$1" commando="$2"
  if [ "$(langs_guard "$commando")" = "2" ]; then
    fail "S11 — wrongly blocked: $omschrijving ($commando)"
  fi
}

geblokkeerd "reset --hard"          "git reset --hard"
geblokkeerd "reset --hard HEAD~1"   "git reset --hard HEAD~1"
geblokkeerd "clean -fd"             "git clean -fd"
geblokkeerd "clean -f"              "git clean -f"
geblokkeerd "clean --force"         "git clean --force"
geblokkeerd "branch -D"             "git branch -D feature/oud"
geblokkeerd "checkout ."            "git checkout ."
geblokkeerd "checkout -- ."         "git checkout -- ."
geblokkeerd "restore ."             "git restore ."
geblokkeerd "in a chain"            "git add . && git reset --hard"
geblokkeerd "branch --delete --force" "git branch --delete --force oud"
geblokkeerd "restore ./."            "git restore ./."
geblokkeerd "checkout ./"            "git checkout ./"

# An environment variable before the command belongs to the invocation, not to
# another program. Without that step, every var prefix bypasses the entire guard - all
# rules at once, not just this one.
geblokkeerd "with env prefix"         "GIT_TRACE=1 git reset --hard"
geblokkeerd "with two env prefixes"  "FOO=bar GIT_TRACE=1 git clean -fd"

# What must NOT be blocked. A false positive blocks work in four
# projects at once, so this weighs heavier than a missed case.
toegestaan "reset without --hard"    "git reset HEAD~1"
toegestaan "reset --soft"           "git reset --soft HEAD~1"
toegestaan "clean -n (dry run)"     "git clean -n"
toegestaan "branch -d (safe)"     "git branch -d feature/klaar"
toegestaan "branch without flag"     "git branch"
toegestaan "checkout of a branch" "git checkout main"
toegestaan "checkout -b"            "git checkout -b feature/nieuw"
toegestaan "restore of a single file" "git restore src/app.ts"
toegestaan "checkout of a single file" "git checkout -- src/app.ts"
toegestaan "status"                 "git status"
toegestaan "not a git command"      "rm -rf build"
toegestaan "the text inside a string" "echo 'gebruik nooit git reset --hard'"

# Only segments that start with `git` are evaluated. Without that requirement,
# every command whose second word happens to be a git subcommand would be
# blocked — and those are ordinary, everyday commands.
toegestaan "make clean with -f"      "make clean -f Makefile"
toegestaan "npm run clean"          "npm run clean -- --force"
toegestaan "docker restore"         "docker restore ."

# Long options are not short-flag clusters. `--exclude=foo` contains an `f` and
# `--set-upstream-to=origin/DEV` a `D`, but neither is destructive.
# These are everyday commands; blocking them is the worst outcome.
toegestaan "clean -n with --exclude"  "git clean -n --exclude=foo"
toegestaan "clean --dry-run"         "git clean --dry-run"

# The rule is that a long option never counts as a short-flag cluster. The two
# cases above do not touch that rule: "--exclude" and "--set-upstream-to"
# do not themselves contain an f or D, only their value. These two do. Whether git
# knows these options today is not the point — git gains more with every version,
# and the guard should not suddenly start reacting to that.
toegestaan "long option containing an f"  "git clean --dry-run --filter=build"
toegestaan "long option containing a D"  "git branch --list --DEV-only"
toegestaan "branch --set-upstream-to" "git branch --set-upstream-to=origin/DEV"
toegestaan "branch --format with D"   "git branch --format=%(refname:short)-DEV"
toegestaan "git with -C"              "git -C /pad status"
toegestaan "env prefix without danger" "GIT_TRACE=1 git status"

# The deliberate escape hatch. A guard without an escape hatch eventually gets
# bypassed by editing the script; so it must exist and be loud.
# The escape hatch must work the way the block message prescribes: as a prefix
# in the command text. A command that has not yet started cannot by definition
# affect the guard's own environment, so testing only the guard's own
# environment would never hit the documented form.
uit_fout="$SANDBOX/uitweg.txt"
printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"CLAUDE_WORKFLOW_GUARDRAILS_UIT=1 git reset --hard"}}' \
  "$werkmap" | "$guard" >/dev/null 2>"$uit_fout"
uit_status=$?

[ "$uit_status" -ne 2 ] || fail "S11 — the escape hatch does not work; the command remained blocked"
[ -s "$uit_fout" ] || fail "S11 — the escape hatch reports nothing; a silent escape hatch is a disabled guard"
grep -qi 'warning' "$uit_fout" || {
  fail "S11 — the escape hatch message is not recognizable as a warning"
  cat "$uit_fout" >&2
}

test_klaar
