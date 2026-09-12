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
  test_klaar
fi

# Two working directories: one on a feature branch, one on main. The guard must
# consult the current branch, because `git push origin HEAD` means something different
# depending on where you are.
op_feature="$(vers_project op-feature)"
git -C "$op_feature" commit -q --allow-empty -m start
git -C "$op_feature" checkout -q -b feature/werk

op_main="$(vers_project op-main)"
git -C "$op_main" commit -q --allow-empty -m start
git -C "$op_main" branch -M main

langs_guard() {
  local commando="$1" map="$2"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$map" "$(printf '%s' "$commando" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

geblokkeerd() {
  local omschrijving="$1" commando="$2" map="$3"
  if [ "$(langs_guard "$commando" "$map")" != "2" ]; then
    fail "S12 — not blocked: $omschrijving ($commando)"
  fi
}
toegestaan() {
  local omschrijving="$1" commando="$2" map="$3"
  if [ "$(langs_guard "$commando" "$map")" = "2" ]; then
    fail "S12 — wrongly blocked: $omschrijving ($commando)"
  fi
}

# Explicit refspecs that hit main — from whichever branch.
geblokkeerd "push origin main"        "git push origin main"        "$op_feature"
geblokkeerd "push origin HEAD:main"   "git push origin HEAD:main"   "$op_feature"
geblokkeerd "push with --force"        "git push --force origin main" "$op_feature"
geblokkeerd "push with +main"          "git push origin +main"       "$op_feature"
geblokkeerd "push that deletes main" "git push origin :main"      "$op_feature"

# --all and --mirror push all branches, so also main - regardless of where you are.
geblokkeerd "push --all"              "git push --all origin"       "$op_feature"
geblokkeerd "push --mirror"           "git push --mirror origin"    "$op_feature"
geblokkeerd "push with env prefix"     "FOO=1 git push origin main"  "$op_feature"

# The state-dependent bare push: only keying on the current branch misses the
# category above, and only keying on refspecs misses this one.
geblokkeerd "bare push on main"       "git push"                    "$op_main"
geblokkeerd "push origin HEAD on main" "git push origin HEAD"       "$op_main"

# Legitimate work must keep working — the SessionEnd hook does exactly this.
toegestaan "push origin HEAD on feature" "git push origin HEAD"     "$op_feature"
toegestaan "bare push on feature"        "git push"                 "$op_feature"
toegestaan "push -u origin HEAD"         "git push -u origin HEAD"  "$op_feature"
toegestaan "push to a feature branch" "git push origin feature/werk" "$op_feature"
toegestaan "push to maintenance"        "git push origin maintenance"  "$op_feature"

test_klaar
