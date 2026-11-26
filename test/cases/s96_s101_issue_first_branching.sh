#!/usr/bin/env bash
# S96-S101, S718 — Issue-first branching: a feature/fix branch must name the
# issue it implements, verified via gh, fail-open, with the native
# pre-commit hook covering non-Claude branch/commit activity.
# Covers: F19, F76

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
    | PATH="${extra_path:+$extra_path:}$nogh" "$guard" 2>&1
}

nogh="$(path_without_gh)"

# S96 — no issue number in the branch name at all: blocked, purely
# syntactically, no gh call needed.
output="$(through_guard "$project" 'git checkout -b feature/no-number' "$nogh")"
status=$?
[ "$status" -eq 2 ] || fail "S96 — branch creation without an issue number was not blocked"
assert_contains "S96 — message points at creating the issue first" "issue" "$output"

# S97 — a successful lookup observes a non-OPEN state: block.
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

# S97b — D8 accepts the risk: even a nonexistent issue warns/allows when
# its lookup fails. Use gh's real diagnostic, not an undifferentiated exit 1.
# Exercise both selectors and all three protected branch families.
for form in 'checkout -b' 'switch -c'; do
  for family in feature fix wip; do
    fake="$(fake_gh_bin '
case "$*" in
  "issue view 999999 --json state --jq .state")
    echo checked >> "$SANDBOX/nonexistent-lookup"
    printf "%s\n" "GraphQL: Could not resolve to an issue or pull request with the number of 999999. (repository.issue)" >&2
    exit 1 ;;
esac
exit 88')"
    rm -f "$SANDBOX/nonexistent-lookup"
    output="$(through_guard "$project" "git $form $family/999999-no-such-issue" "$fake")"; status=$?
    [ -s "$SANDBOX/nonexistent-lookup" ] || fail "S97b/$family/$form — nonexistent issue lookup was not attempted"
    [ "$status" -eq 0 ] || fail "S97b/$family/$form — nonexistent issue lookup failure must allow under D8"
    assert_contains "S97b/$family/$form — lookup failure warns" warning "$output"
  done
done

# S98 — a real, open issue: goes through.
status="$(through_guard "$project" 'git checkout -b feature/7-open-issue' "$(fake_gh_bin '
case "$*" in
  "issue view 7 --json state --jq .state") printf "OPEN"; exit 0 ;;
esac
exit 1
')" >/dev/null 2>&1; echo $?)"
[ "$status" != "2" ] || fail "S98 — branch creation against an open issue was wrongly blocked"

# S99 — failed, empty or unavailable lookup warns and allows (D8),
# including a failed command that happens to print CLOSED.
output="$(through_guard "$project" 'git checkout -b feature/7-open-issue' "$nogh")"
status=$?
[ "$status" -ne 2 ] || fail "S99a — gh missing, but branch creation was blocked anyway"
assert_contains "S99a — warns that the check was skipped" "warning" "$output"

output="$(through_guard "$project" 'git checkout -b feature/7-open-issue' "$(fake_gh_bin 'exit 1')")"
status=$?
[ "$status" -ne 2 ] || fail "S99b — gh unreachable, but branch creation was blocked anyway"
assert_contains "S99b — warns that the check was skipped" "warning" "$output"

for result in empty failed-nonopen; do
  if [ "$result" = empty ]; then body='exit 0'; else body='echo CLOSED; exit 1'; fi
  output="$(through_guard "$project" 'git checkout -b feature/7-example' "$(fake_gh_bin "$body")")"; status=$?
  [ "$status" -eq 0 ] || fail "S99/$result — unverified lookup must allow"
  assert_contains "S99/$result — skipped lookup warns" warning "$output"
done

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

# S718 (#706 AC8-AC11): candidate-only WIP coverage. S97/S97b/S99
# above follow AC9 as settled by maintainer decision D8.
# Both selectors and the shared pattern have independent falsifiers.
. "$TEST_REPO_ROOT/hooks/rules.sh"
[[ wip/706-example =~ $BRANCH_ISSUE_PATTERN ]] || fail "S718/regex — numbered WIP is absent from the shared syntax rule"
for form in 'checkout -b' 'switch -c'; do
  for bad in no-number 706-UPPER 706- 706-bad/child; do
    output="$(through_guard "$project" "git $form wip/$bad" "$nogh")"; status=$?
    [ "$status" -eq 2 ] || fail "S718/syntax/$form/$bad — malformed WIP creation must block"
  done
  fake="$(fake_gh_bin '
case "$*" in
  "issue view 706 --json state --jq .state") echo OPEN; echo checked >> "$SANDBOX/wip-lookup"; exit 0 ;;
esac
exit 1')"
  rm -f "$SANDBOX/wip-lookup"
  output="$(through_guard "$project" "git $form wip/706-example" "$fake")"; status=$?
  [ "$status" -eq 0 ] || fail "S718/open/$form — numbered OPEN WIP must pass"
  [ -s "$SANDBOX/wip-lookup" ] || fail "S718/lookup/$form — OPEN WIP creation must actually verify its issue"
  output="$(through_guard "$project" "git $form wip/706-example" "$(fake_gh_bin 'echo CLOSED; exit 0')")"; status=$?
  [ "$status" -eq 2 ] || fail "S718/closed/$form — verified CLOSED WIP must block"
  for unavailable in missing failed empty failed-nonopen; do
    case "$unavailable" in
      missing) fake="$nogh" ;;
      failed) fake="$(fake_gh_bin 'exit 1')" ;;
      empty) fake="$(fake_gh_bin 'exit 0')" ;;
      failed-nonopen) fake="$(fake_gh_bin 'echo CLOSED; exit 1')" ;;
    esac
    output="$(through_guard "$project" "git $form wip/706-example" "$fake")"; status=$?
    [ "$status" -eq 0 ] || fail "S718/unverified/$form/$unavailable — unavailable lookup must fail open"
    assert_contains "S718/warning/$form/$unavailable" warning "$output"
  done

  # Preservation controls: feature/fix keep their existing classification.
  for family in feature fix; do
    output="$(through_guard "$project" "git $form $family/no-number" "$nogh")"; status=$?
    [ "$status" -eq 2 ] || fail "AC11/control/$family/$form/syntax"
    output="$(through_guard "$project" "git $form $family/706-example" "$(fake_gh_bin 'echo OPEN; exit 0')")"; status=$?
    [ "$status" -eq 0 ] || fail "AC11/control/$family/$form/open"
    output="$(through_guard "$project" "git $form $family/706-example" "$(fake_gh_bin 'echo CLOSED; exit 0')")"; status=$?
    [ "$status" -eq 2 ] || fail "AC11/control/$family/$form/closed"
    for unavailable in missing failed empty failed-nonopen; do
      case "$unavailable" in
        missing) fake="$nogh" ;;
        failed) fake="$(fake_gh_bin 'exit 1')" ;;
        empty) fake="$(fake_gh_bin 'exit 0')" ;;
        failed-nonopen) fake="$(fake_gh_bin 'echo CLOSED; exit 1')" ;;
      esac
      output="$(through_guard "$project" "git $form $family/706-example" "$fake")"; status=$?
      [ "$status" -eq 0 ] || fail "AC11/control/$family/$form/$unavailable"
      assert_contains "AC11/control/$family/$form/$unavailable/warning" warning "$output"
    done
  done
  for branch in release/742-process-hygiene scratch/example; do
    output="$(through_guard "$project" "git $form $branch" "$nogh")"; status=$?
    [ "$status" -eq 0 ] || fail "AC11/control/$branch/$form"
  done
done
for verb in checkout switch; do
  for branch in main feature/no-number fix/no-number wip/no-number release/example scratch/example; do
    output="$(through_guard "$project" "git $verb $branch" "$nogh")"; status=$?
    [ "$status" -eq 0 ] || fail "AC11/control/plain-$verb/$branch"
  done
done

# The only native link installed here belongs to this test sandbox. Direct
# execution would silently test pre-commit's non-symlink fail-open path.
wip_native="$(fresh_project wip-native-706)"
ln -s "$TEST_REPO_ROOT/hooks/pre-commit" "$wip_native/.git/hooks/pre-commit"
git -C "$wip_native" commit -q --allow-empty -m first >/dev/null 2>&1 || fail "AC11/control/unborn-main"
for family in wip feature fix; do
  git -C "$wip_native" checkout -q -b "$family/no-number"
  native_output="$(git -C "$wip_native" commit -q --allow-empty -m malformed 2>&1)"; native_status=$?
  [ "$native_status" -ne 0 ] || fail "S718/native/$family — malformed native commit must block"
  assert_contains "S718/native-reason/$family" "$REASON_BRANCH_NO_ISSUE" "$native_output"
  # Escape hatch is scoped to one command inside this disposable fixture.
  CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$wip_native" commit -q --allow-empty -m escape >/dev/null 2>&1 || fail "AC11/control/escape/$family"
  git -C "$wip_native" checkout -q -b "$family/706-example"
  git -C "$wip_native" commit -q --allow-empty -m numbered >/dev/null 2>&1 || fail "S718/native-numbered/$family"
done
for branch in release/742-example scratch/example; do
  git -C "$wip_native" checkout -q -b "$branch"
  git -C "$wip_native" commit -q --allow-empty -m unrelated >/dev/null 2>&1 || fail "AC11/control/native/$branch"
done
git -C "$wip_native" checkout -q main
native_output="$(git -C "$wip_native" commit -q --allow-empty -m protected 2>&1)"; native_status=$?
[ "$native_status" -ne 0 ] || fail "AC11/control/native-main"
CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$wip_native" commit -q --allow-empty -m escape >/dev/null 2>&1 || fail "AC11/control/escape-main"

test_done
