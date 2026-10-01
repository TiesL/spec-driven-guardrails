#!/usr/bin/env bash
# S165 — test/lib.sh isolates fixture git commands from an inherited git repo environment.
# Covers: F1
#
# Issue #377 (AC4). A hook, `git rebase --exec` or a git alias exports
# repo-local variables (GIT_DIR, GIT_INDEX_FILE, ...) to everything it
# launches. Before #377, a fixture `git -C <fixture> ...` in a test then
# acted on the launching repo instead of the fixture. This test points
# those variables at a *decoy repo inside its own sandbox* (never at the
# real repo, never at TEST_REPO_ROOT), runs the shared fixture helpers in a
# child process, and asserts the decoy is unchanged.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Hermetic outer process: whatever launched this test, the decoy set-up
# and snapshots below must never reach the launching repo. git's own list,
# read at runtime (no copy of the list in this file).
for _v in $(git rev-parse --local-env-vars 2>/dev/null); do unset "$_v"; done

sandbox_create
trap sandbox_destroy EXIT

local_vars="$(git rev-parse --local-env-vars)"
[ -n "$local_vars" ] || { fail "S165 — git rev-parse --local-env-vars printed nothing"; test_done; }

# Given: a decoy repo with one commit, one branch, no tags.
decoy="$SANDBOX/decoy"
git init -q -b main "$decoy"
echo decoy > "$decoy/decoy.txt"
git -C "$decoy" add decoy.txt
git -C "$decoy" commit -q -m "decoy commit"

snap_decoy() {
  echo "## refs"; git -C "$decoy" for-each-ref --format='%(refname) %(objectname)'
  echo "## HEAD"; git -C "$decoy" symbolic-ref -q HEAD; git -C "$decoy" rev-parse HEAD
  echo "## worktrees"; git -C "$decoy" worktree list --porcelain
  echo "## config"; cat "$decoy/.git/config"
  echo "## index"; git -C "$decoy" ls-files -s
  echo "## stash"; git -C "$decoy" stash list
}
snap_decoy > "$SANDBOX/decoy.before"

# A value for each repo-local variable that points at the decoy, the way a
# real launcher's values point at the launching repo. Unknown future names
# get a harmless placeholder.
decoy_value() {
  case "$1" in
    GIT_DIR|GIT_COMMON_DIR) echo "$decoy/.git" ;;
    GIT_WORK_TREE) echo "$decoy" ;;
    GIT_INDEX_FILE) echo "$decoy/.git/index" ;;
    GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES) echo "$decoy/.git/objects" ;;
    GIT_CONFIG) echo "$decoy/.git/config" ;;
    GIT_CONFIG_PARAMETERS) echo "'decoy.marker'='1'" ;;
    GIT_CONFIG_COUNT) echo "0" ;;
    GIT_GRAFT_FILE) echo "$decoy/.git/info/grafts" ;;
    GIT_SHALLOW_FILE) echo "$decoy/.git/shallow" ;;
    GIT_NO_REPLACE_OBJECTS|GIT_IMPLICIT_WORK_TREE) echo "1" ;;
    GIT_REPLACE_REF_BASE) echo "refs/replace/" ;;
    GIT_PREFIX) echo "" ;;
    *) echo "decoy" ;;
  esac
}

# Runs $1 (a bash snippet) in a child process with every repo-local
# variable exported to point at the decoy, after sourcing test/lib.sh.
run_with_decoy_env() {
  (
    for v in $local_vars; do
      export "$v=$(decoy_value "$v")"
    done
    bash -c '. "$TEST_REPO_ROOT/test/lib.sh"; '"$1"
  )
}

# --- Case 1: sourcing lib.sh clears every variable git lists. ------------
# shellcheck disable=SC2016  # the child's own script body, expanded when it runs
still_set="$(run_with_decoy_env '
  for v in $(env -i PATH="$PATH" git rev-parse --local-env-vars); do
    if [ -n "${!v+x}" ]; then echo "$v"; fi
  done')"
[ -z "$still_set" ] || fail "S165 — still set after sourcing test/lib.sh: $(tr '\n' ' ' <<<"$still_set")"

# --- Case 2: the shared fixture helpers leave the decoy unchanged. -------
# fresh_project, a fixture commit, a tag, `git init --bare`, `remote add`
# and `push -u`: the same command shapes as S57, S84 and S144, which moved
# the real main, created a tag and set core.bare=true (issue #377).
# shellcheck disable=SC2016  # the child's own script body, expanded when it runs
fixture_output="$(run_with_decoy_env '
  sandbox_create
  trap sandbox_destroy EXIT
  f="$(fresh_project fixture)"
  echo fixture > "$f/fixture.txt"
  git -C "$f" add fixture.txt
  git -C "$f" commit -q -m "fixture commit"
  git -C "$f" tag fixture-tag
  git -C "$f" checkout -q -b feature/1-fixture
  git init -q --bare "$SANDBOX/remote.git"
  git -C "$f" remote add origin "$SANDBOX/remote.git"
  git -C "$f" push -q -u origin feature/1-fixture
  echo "fixture HEAD subject: $(git -C "$f" log -1 --format=%s 2>/dev/null)"
' 2>&1)"
snap_decoy > "$SANDBOX/decoy.after"
if ! diff -u "$SANDBOX/decoy.before" "$SANDBOX/decoy.after" > "$SANDBOX/decoy.diff" 2>&1; then
  fail "S165 — fixture git commands under test/lib.sh changed the decoy repo:"
  cat "$SANDBOX/decoy.diff" >&2
  echo "    child output: $fixture_output" >&2
fi
assert_contains "S165 — the fixture commit landed in the fixture itself" \
  "fixture HEAD subject: fixture commit" "$fixture_output"

# --- Case 3: sandbox_guard refuses loudly when a variable is re-exported -
# after sourcing (same refusal shape as for HOME, S3).
for v in $local_vars; do
  guard_output="$(bash -c '
    . "$TEST_REPO_ROOT/test/lib.sh"
    sandbox_create
    trap sandbox_destroy EXIT
    export '"$v"'=re-exported
    sandbox_guard' 2>&1)"
  guard_status=$?
  if [ "$guard_status" -eq 0 ]; then
    fail "S165 — sandbox_guard accepted a re-exported $v"
  else
    assert_contains "S165 — sandbox_guard names the re-exported variable" "$v" "$guard_output"
  fi
done

# --- Case 4: what is not repo-local is left alone. -----------------------
# The test identity, config isolation, the guardrails override and other
# non-repo-local git settings must survive sourcing lib.sh.
kept_output="$(
  export GIT_AUTHOR_NAME="kept author" GIT_COMMITTER_EMAIL="kept@example.invalid"
  export GIT_CONFIG_GLOBAL="$SANDBOX/kept-gitconfig" GIT_CONFIG_NOSYSTEM=1
  export GIT_TERMINAL_PROMPT=0 GIT_EDITOR=true CLAUDE_WORKFLOW_GUARDRAILS_OFF=1
  bash -c '. "$TEST_REPO_ROOT/test/lib.sh"
    for v in GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM \
             GIT_TERMINAL_PROMPT GIT_EDITOR CLAUDE_WORKFLOW_GUARDRAILS_OFF; do
      echo "$v=${!v-<unset>}"
    done'
)"
for expected in "GIT_AUTHOR_NAME=kept author" "GIT_COMMITTER_EMAIL=kept@example.invalid" \
                "GIT_CONFIG_GLOBAL=$SANDBOX/kept-gitconfig" "GIT_CONFIG_NOSYSTEM=1" \
                "GIT_TERMINAL_PROMPT=0" "GIT_EDITOR=true" "CLAUDE_WORKFLOW_GUARDRAILS_OFF=1"; do
  assert_contains "S165 — sourcing test/lib.sh keeps a non-repo-local variable" "$expected" "$kept_output"
done

test_done
