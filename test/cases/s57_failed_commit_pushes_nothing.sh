#!/usr/bin/env bash
# S57 — A failed commit or missing network pushes nothing.
# Covers: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

hook="$TEST_REPO_ROOT/hooks/push-after-commit"
[ -x "$hook" ] || { fail "S57 — hooks/push-after-commit is missing"; test_done; }

# Case 1: no origin — the hook must not hang and must not print anything to
# stderr that looks like an error.
project="$(fresh_project no-origin)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work
git -C "$project" commit -q --allow-empty -m "work without remote"

input1='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git commit -m x"}}'
status1=0
printf '%s' "$input1" | "$hook" >/dev/null 2>/dev/null || status1=$?
[ "$status1" -eq 0 ] || fail "S57/case1 — no origin gave exit $status1 instead of 0"

# Case 2: nothing happens on main regardless, even when the remote does
# exist — the same boundary as the existing SessionEnd hook.
project_main="$(fresh_project on-main)"
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project_main" remote add origin "$remote"
git -C "$project_main" commit -q --allow-empty -m start

input2='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project_main"'","tool_input":{"command":"git commit -m x"}}'
printf '%s' "$input2" | "$hook" >/dev/null 2>&1

if git -C "$remote" rev-parse --verify --quiet main >/dev/null 2>&1; then
  fail "S57/case2 — main was pushed after all from push-after-commit"
fi

# Case 3: a command that is not a git commit pushes nothing — no attempt at
# all, even though there is a remote and a feature branch with unpushed work.
project_other="$(fresh_project different-command)"
git -C "$project_other" remote add origin "$remote"
git -C "$project_other" commit -q --allow-empty -m start
git -C "$project_other" checkout -q -b feature/something
git -C "$project_other" commit -q --allow-empty -m "not pushed yet"

input3='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project_other"'","tool_input":{"command":"git status"}}'
printf '%s' "$input3" | "$hook" >/dev/null 2>&1

if git -C "$remote" rev-parse --verify --quiet feature/something >/dev/null 2>&1; then
  fail "S57/case3 — a non-commit command triggered a push after all"
fi

# Case 4: the routine amend/rebase case, from the review on PR #76.
# `git commit --amend` succeeds locally but the subsequent push is rejected
# by origin (non-fast-forward) — that is not a network or access problem,
# and the hook must not label it as such, and certainly must not silently
# force it.
project_amend="$(fresh_project amend)"
git -C "$project_amend" remote add origin "$remote"
git -C "$project_amend" commit -q --allow-empty -m start
git -C "$project_amend" checkout -q -b feature/amend
git -C "$project_amend" commit -q --allow-empty -m "first version"
git -C "$project_amend" push -q -u origin feature/amend
git -C "$project_amend" commit -q --amend --allow-empty -m "rewritten version"
sha_before_amend_on_remote="$(git -C "$remote" rev-parse feature/amend)"

input4='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project_amend"'","tool_input":{"command":"git commit --amend -m x"}}'
output4="$(printf '%s' "$input4" | "$hook" 2>&1)"
status4=$?

[ "$status4" -eq 0 ] || fail "S57/case4 — a rejected push (non-fast-forward) blocked the command (exit $status4)"
[ "$(git -C "$remote" rev-parse feature/amend)" = "$sha_before_amend_on_remote" ] \
  || fail "S57/case4 — the hook silently forced the push, the remote SHA changed"
case "$output4" in
  *"local history diverges"*) ;;
  *) fail "S57/case4 — the message does not mention that local history diverges (amend/rebase), but: $output4" ;;
esac
case "$output4" in
  *"no network or no access"*)
    fail "S57/case4 — the message wrongly blames the amend case on network/access: $output4" ;;
esac

test_done
