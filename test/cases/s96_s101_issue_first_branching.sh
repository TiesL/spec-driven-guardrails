#!/usr/bin/env bash
# S96-S101 — Issue-first branching: a feature/fix branch must name the
# issue it implements, verified via gh, fail-open, with the native
# pre-commit hook covering non-Claude branch/commit activity.
# Covers: F19

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S96 — hooks/git-guardrails is missing"; test_done; }

project="$(fresh_project issue-first)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" branch -M main

through_guard() {
  local dir="$1" command="$2" extra_path="${3:-}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$dir" "$(printf '%s' "$command" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | PATH="${extra_path:+$extra_path:}$PATH" "$guard" 2>&1
}

nogh="$(path_without_gh)"

# S96 — no issue number in the branch name at all: blocked, purely
# syntactically, no gh call needed.
output="$(through_guard "$project" 'git checkout -b feature/no-number' "$nogh")"
status=$?
[ "$status" -eq 2 ] || fail "S96 — branch creation without an issue number was not blocked"
assert_contains "S96 — message points at creating the issue first" "issue" "$output"

# S97 — the number is there, but the issue is closed.
# fake_gh_bin always writes to the same $SANDBOX/fakegh path, so each
# variant is built fresh right before it's used — holding onto an earlier
# path and reusing it later would silently pick up whatever script was
# built last.
status="$(through_guard "$project" 'git checkout -b feature/7-closed-issue' "$(fake_gh_bin '
case "$*" in
  "issue view 7 --json state --jq .state") printf "CLOSED"; exit 0 ;;
esac
exit 1
')" >/dev/null 2>&1; echo $?)"
[ "$status" = "2" ] || fail "S97 — branch creation against a closed issue was not blocked"

# S97b — the number is there, but no such issue exists (gh errors).
status="$(through_guard "$project" 'git checkout -b feature/999-no-such-issue' "$(fake_gh_bin 'exit 1')" >/dev/null 2>&1; echo $?)"
# A gh error is indistinguishable from "no network" here (S99) — both fail
# open, by design (same rule as the merge guard). This case documents that
# choice rather than asserting a block.
[ "$status" != "2" ] || fail "S97b — an unreachable gh was treated as a hard block instead of failing open"

# S98 — a real, open issue: goes through.
status="$(through_guard "$project" 'git checkout -b feature/7-open-issue' "$(fake_gh_bin '
case "$*" in
  "issue view 7 --json state --jq .state") printf "OPEN"; exit 0 ;;
esac
exit 1
')" >/dev/null 2>&1; echo $?)"
[ "$status" != "2" ] || fail "S98 — branch creation against an open issue was wrongly blocked"

# S99 — gh missing entirely, or network unreachable: fails open, with a
# warning, exactly like the merge guard (S17).
output="$(through_guard "$project" 'git checkout -b feature/7-open-issue' "$nogh")"
status=$?
[ "$status" -ne 2 ] || fail "S99a — gh missing, but branch creation was blocked anyway"
assert_contains "S99a — warns that the check was skipped" "warning" "$output"

output="$(through_guard "$project" 'git checkout -b feature/7-open-issue' "$(fake_gh_bin 'exit 1')")"
status=$?
[ "$status" -ne 2 ] || fail "S99b — gh unreachable, but branch creation was blocked anyway"
assert_contains "S99b — warns that the check was skipped" "warning" "$output"

# S96 (switch form) — `git switch -c` is judged the same way as `checkout -b`.
status="$(through_guard "$project" 'git switch -c feature/no-number' "$nogh" >/dev/null 2>&1; echo $?)"
[ "$status" = "2" ] || fail "S96b — git switch -c without an issue number was not blocked"

# S101 — an existing branch, checked out without -b/-c: never judged.
git -C "$project" checkout -q -b feature/1-existing
git -C "$project" checkout -q main
status="$(through_guard "$project" 'git checkout feature/1-existing' "$nogh" >/dev/null 2>&1; echo $?)"
[ "$status" != "2" ] || fail "S101 — checking out an existing branch was wrongly blocked"

# S100 — the native pre-commit hook covers the same rule outside Claude.
native_project="$(fresh_project issue-first-native)"
adopt "$native_project"
git -C "$native_project" commit -q --allow-empty -m start
git -C "$native_project" checkout -q -b feature/no-number
native_output="$(cd "$native_project" && git commit -q --allow-empty -m "on branch" 2>&1)"
native_status=$?
[ "$native_status" -ne 0 ] || fail "S100 — a non-Claude commit on an unnumbered branch was not blocked"
assert_contains "S100 — message names the missing issue number" "issue" "$native_output"

# And: a correctly-named branch just proceeds (native hook does syntax only,
# no gh call, so no fake gh is needed here).
git -C "$native_project" checkout -q -b feature/1-numbered
if ! git -C "$native_project" commit -q --allow-empty -m "on numbered branch" 2>&1; then
  fail "S100 — a legitimate commit on a numbered branch was blocked"
fi

test_done
