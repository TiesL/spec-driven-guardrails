#!/usr/bin/env bash
# S46 — The branch is determined in the repo the command is about.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S46 — hooks/git-guardrails is missing"; test_done; }

on_main="$(fresh_project on-main)"
git -C "$on_main" commit -q --allow-empty -m start
git -C "$on_main" branch -M main

on_feature="$(fresh_project on-feature)"
git -C "$on_feature" commit -q --allow-empty -m start
git -C "$on_feature" checkout -q -b feature/work

langs_guard() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$1" "$(printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

# Given: the session is on main, the command is about a repo on a
# feature branch. If the guard looked at the session directory, it would block
# legitimate work in another repo.
if [ "$(langs_guard "$on_main" "git -C $on_feature push origin HEAD")" = "2" ]; then
  fail "S46 — push in another repo blocked based on the session directory"
fi

# And conversely: the session is on a feature branch, the command is about a
# repo on main. That should indeed be blocked.
if [ "$(langs_guard "$on_feature" "git -C $on_main push origin HEAD")" != "2" ]; then
  fail "S46 — push to main in another repo let through"
fi

# --git-dir and --work-tree count just as much; git itself works out how they
# relate. Here only that the guard no longer swallows them as an ordinary flag,
# because then the subcommand would disappear from view.
if [ "$(langs_guard "$on_feature" "git --git-dir $on_main/.git --work-tree $on_main push origin HEAD")" != "2" ]; then
  fail "S46 — --git-dir/--work-tree are not taken into account in the branch determination"
fi
if [ "$(langs_guard "$on_feature" "git --git-dir /tmp/does-not-exist reset --hard")" != "2" ]; then
  fail "S46 — a destructive command with --git-dir is no longer recognized"
fi

# If the path does not exist or is not a repo, no branch comes out. Do not
# block: when in doubt, allow.
no_repo="$SANDBOX/no-repo"
mkdir -p "$no_repo"
if [ "$(langs_guard "$on_feature" "git -C $no_repo push origin HEAD")" = "2" ]; then
  fail "S46 — blocked while the target path is not a git repo"
fi
if [ "$(langs_guard "$on_feature" "git -C /does/not/really/exist push origin HEAD")" = "2" ]; then
  fail "S46 — blocked while the target path does not exist"
fi

test_done
