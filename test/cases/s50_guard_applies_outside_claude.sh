#!/usr/bin/env bash
# S50 — The guard also applies outside of Claude.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project native-hooks)"
adopt "$project"

# A real bare remote, otherwise git push origin main never reaches the
# pre-push hook — git would already fail earlier on "no remote", and that
# would let this test demonstrate something quite different than intended.
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"

# Given: main checked out, the git hooks installed (by adopt). First one
# allowed first commit — a repo without commits is allowed to have its very
# first commit on main (same exception as in hooks/git-guardrails) — so that
# the second attempt below really puts the rule to the test.
[ -L "$project/.git/hooks/pre-commit" ] || fail "S50 — pre-commit is not a symlink after adopt.sh"
[ -L "$project/.git/hooks/pre-push" ] || fail "S50 — pre-push is not a symlink after adopt.sh"
git -C "$project" commit -q --allow-empty -m "first commit, allowed on main" \
  || fail "S50 — the very first commit (exception) was wrongly refused"

# When: git commit directly in a shell, without Claude in between.
output="$(cd "$project" && git commit -q --allow-empty -m "rechtstreeks op main" 2>&1)"
status=$?

# Then: refused, with the same message as the PreToolUse guard.
[ "$status" -ne 0 ] || fail "S50 — commit on main via a direct git call was not refused"
assert_contains "S50 — the message matches the PreToolUse guard" "main gets its changes via a PR" "$output"

# And: on a feature branch it just proceeds — the same rule, not a
# blanket block of everything.
git -C "$project" checkout -q -b feature/1-something
if ! git -C "$project" commit -q --allow-empty -m "on a branch" 2>&1; then
  fail "S50 — a legitimate commit on a feature branch was blocked"
fi

# And git push origin main directly, also without Claude.
git -C "$project" checkout -q main
git -C "$project" branch -q --unset-upstream 2>/dev/null || true
push_output="$(cd "$project" && git push origin main 2>&1)"
push_status=$?
[ "$push_status" -ne 0 ] || fail "S50 — git push origin main was not refused"
assert_contains "S50 — the push message matches the PreToolUse guard" "main gets its changes via a PR" "$push_output"

# And: a relative SPEC_DRIVEN_GUARDRAILS_DIR must not make the symlink dangling.
# Found in the review on PR #76: a relative path resolves from the directory
# of the symlink itself (.git/hooks/), not from the directory adopt.sh was
# run from — and git silently skips a dangling git hook, without any
# message. Demonstrated exactly with a real relative path, not reasoned
# about: calling adopt.sh from a subdirectory of $TEST_REPO_ROOT with
# a relative SPEC_DRIVEN_GUARDRAILS_DIR.
project_relative="$(fresh_project relative-workflow-dir)"
(
  cd "$TEST_REPO_ROOT/hooks" || exit 1
  SPEC_DRIVEN_GUARDRAILS_DIR=".." "$TEST_REPO_ROOT/adopt.sh" "$project_relative" >/dev/null 2>&1
)
target="$(readlink "$project_relative/.git/hooks/pre-commit" 2>/dev/null)"
case "$target" in
  /*) ;;
  *) fail "S50 — a relative SPEC_DRIVEN_GUARDRAILS_DIR produced a non-absolute symlink target: $target" ;;
esac
[ -e "$project_relative/.git/hooks/pre-commit" ] \
  || fail "S50 — the pre-commit symlink is dangling after a relative SPEC_DRIVEN_GUARDRAILS_DIR"

git -C "$project_relative" commit -q --allow-empty -m "first commit"
relative_output="$(cd "$project_relative" && git commit -q --allow-empty -m "second, on main" 2>&1)"
relative_status=$?
[ "$relative_status" -ne 0 ] \
  || fail "S50 — with a relative SPEC_DRIVEN_GUARDRAILS_DIR the git hook did not block (dangling symlink, silently skipped by git)"

test_done
