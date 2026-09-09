#!/usr/bin/env bash
# S47 — Committing on main is blocked, with a workable way out.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S47 — hooks/git-guardrails is missing"; test_klaar; }

langs_guard() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$1" "$(printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

op_main="$(vers_project op-main)"
git -C "$op_main" commit -q --allow-empty -m start
git -C "$op_main" branch -M main

op_feature="$(vers_project op-feature)"
git -C "$op_feature" commit -q --allow-empty -m start
git -C "$op_feature" checkout -q -b feature/werk

# A repo without even a single commit: HEAD does not yet exist.
vers="$(vers_project vers)"

# Then: committing on main is blocked.
[ "$(langs_guard "$op_main" 'git commit -m "iets"')" = "2" ] \
  || fail "S47 — committing on main was not blocked"
[ "$(langs_guard "$op_main" 'git commit --amend')" = "2" ] \
  || fail "S47 — amending on main was not blocked"

# And: the message mentions the way out and that nothing gets lost. Without
# those two, the work stays uncommitted, and that is less safe than what was just stopped.
melding="$SANDBOX/melding.txt"
printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' \
  "$op_main" | "$guard" >/dev/null 2>"$melding"

grep -q 'checkout -b' "$melding" || {
  fail "S47 — the message does not mention how to create a branch"
  cat "$melding" >&2
}
grep -qi 'come along unchanged\|nothing gets lost' "$melding" \
  || fail "S47 — the message does not say that the changes come along"

# And: on a feature branch, committing just proceeds.
[ "$(langs_guard "$op_feature" 'git commit -m "iets"')" != "2" ] \
  || fail "S47 — committing on a feature branch was blocked"

# And: the very first commit of a new project is on main by definition.
[ "$(langs_guard "$vers" 'git commit -m "eerste commit"')" != "2" ] \
  || fail "S47 — the first commit of an empty repo was blocked"

# And branching remains of course simply possible — otherwise the way out is closed.
[ "$(langs_guard "$op_main" 'git checkout -b feature/nieuw')" != "2" ] \
  || fail "S47 — branching from main was blocked; the way out is then closed"

test_klaar
