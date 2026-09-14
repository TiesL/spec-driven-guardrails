#!/usr/bin/env bash
# S47 — Committing on main is blocked, with a workable way out.
# Covers: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S47 — hooks/git-guardrails is missing"; test_done; }

langs_guard() {
  local dir="$1" command="$2" extra_path="${3:-}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$dir" "$(printf '%s' "$command" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | PATH="${extra_path:+$extra_path:}$PATH" "$guard" >/dev/null 2>&1
  echo $?
}

on_main="$(fresh_project on-main)"
git -C "$on_main" commit -q --allow-empty -m start
git -C "$on_main" branch -M main

on_feature="$(fresh_project on-feature)"
git -C "$on_feature" commit -q --allow-empty -m start
git -C "$on_feature" checkout -q -b feature/work

# A repo without even a single commit: HEAD does not yet exist.
fresh="$(fresh_project fresh)"

# Then: committing on main is blocked.
[ "$(langs_guard "$on_main" 'git commit -m "something"')" = "2" ] \
  || fail "S47 — committing on main was not blocked"
[ "$(langs_guard "$on_main" 'git commit --amend')" = "2" ] \
  || fail "S47 — amending on main was not blocked"

# And: the message mentions the way out and that nothing gets lost. Without
# those two, the work stays uncommitted, and that is less safe than what was just stopped.
message="$SANDBOX/message.txt"
printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' \
  "$on_main" | "$guard" >/dev/null 2>"$message"

grep -q 'checkout -b' "$message" || {
  fail "S47 — the message does not mention how to create a branch"
  cat "$message" >&2
}
grep -qi 'come along unchanged\|nothing gets lost' "$message" \
  || fail "S47 — the message does not say that the changes come along"

# And: on a feature branch, committing just proceeds.
[ "$(langs_guard "$on_feature" 'git commit -m "something"')" != "2" ] \
  || fail "S47 — committing on a feature branch was blocked"

# And: the very first commit of a new project is on main by definition.
[ "$(langs_guard "$fresh" 'git commit -m "eerste commit"')" != "2" ] \
  || fail "S47 — the first commit of an empty repo was blocked"

# And branching remains of course simply possible — otherwise the way out is closed.
[ "$(langs_guard "$on_main" 'git checkout -b feature/1-nieuw' "$(path_without_gh)")" != "2" ] \
  || fail "S47 — branching from main was blocked; the way out is then closed"

test_done
