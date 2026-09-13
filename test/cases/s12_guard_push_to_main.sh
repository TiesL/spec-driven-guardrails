#!/usr/bin/env bash
# S12 — Push to main is blocked, also via refspec.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
if [ ! -x "$guard" ]; then
  fail "S12 — hooks/git-guardrails is missing"
  test_done
fi

# Two working directories: one on a feature branch, one on main. The guard must
# consult the current branch, because `git push origin HEAD` means something different
# depending on where you are.
on_feature="$(fresh_project on-feature)"
git -C "$on_feature" commit -q --allow-empty -m start
git -C "$on_feature" checkout -q -b feature/work

on_main="$(fresh_project on-main)"
git -C "$on_main" commit -q --allow-empty -m start
git -C "$on_main" branch -M main

through_guard() {
  local command="$1" dir="$2"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$dir" "$(printf '%s' "$command" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

blocked() {
  local description="$1" command="$2" dir="$3"
  if [ "$(through_guard "$command" "$dir")" != "2" ]; then
    fail "S12 — not blocked: $description ($command)"
  fi
}
allowed() {
  local description="$1" command="$2" dir="$3"
  if [ "$(through_guard "$command" "$dir")" = "2" ]; then
    fail "S12 — wrongly blocked: $description ($command)"
  fi
}

# Explicit refspecs that hit main — from whichever branch.
blocked "push origin main"        "git push origin main"        "$on_feature"
blocked "push origin HEAD:main"   "git push origin HEAD:main"   "$on_feature"
blocked "push with --force"        "git push --force origin main" "$on_feature"
blocked "push with +main"          "git push origin +main"       "$on_feature"
blocked "push that deletes main" "git push origin :main"      "$on_feature"

# --all and --mirror push all branches, so also main - regardless of where you are.
blocked "push --all"              "git push --all origin"       "$on_feature"
blocked "push --mirror"           "git push --mirror origin"    "$on_feature"
blocked "push with env prefix"     "FOO=1 git push origin main"  "$on_feature"

# The state-dependent bare push: only keying on the current branch misses the
# category above, and only keying on refspecs misses this one.
blocked "bare push on main"       "git push"                    "$on_main"
blocked "push origin HEAD on main" "git push origin HEAD"       "$on_main"

# Legitimate work must keep working — the SessionEnd hook does exactly this.
allowed "push origin HEAD on feature" "git push origin HEAD"     "$on_feature"
allowed "bare push on feature"        "git push"                 "$on_feature"
allowed "push -u origin HEAD"         "git push -u origin HEAD"  "$on_feature"
allowed "push to a feature branch" "git push origin feature/work" "$on_feature"
allowed "push to maintenance"        "git push origin maintenance"  "$on_feature"

test_done
