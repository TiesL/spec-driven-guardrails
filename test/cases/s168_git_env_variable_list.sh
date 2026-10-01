#!/usr/bin/env bash
# S168 — lib/git-env.sh clears git's own repo-local list plus a fixed floor, and nothing else.
# Covers: F1
#
# Issue #377, Architect decision A19: `git_local_env_vars` is the union of
# `git rev-parse --local-env-vars` (read at runtime) and a fixed floor, so a
# newer git that adds a name is covered and a git where the command fails
# never clears fewer. Identity, config isolation and the guardrails
# override are never cleared. One copy of the list only.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Hermetic outer process (see S165): git's own list, read at runtime.
for _v in $(git rev-parse --local-env-vars 2>/dev/null); do unset "$_v"; done

sandbox_create
trap sandbox_destroy EXIT

library="$TEST_REPO_ROOT/lib/git-env.sh"
if [ ! -f "$library" ]; then
  fail "S168 — lib/git-env.sh does not exist"
  test_done
fi
# shellcheck source=../../lib/git-env.sh
. "$library"

runtime_list="$(git rev-parse --local-env-vars | sort -u)"
[ -n "$runtime_list" ] || { fail "S168 — git rev-parse --local-env-vars printed nothing"; test_done; }

# Prints the names of $1 (a newline list) missing from $2 (a newline list).
missing_from() {
  comm -23 <(printf '%s\n' "$1" | sort -u) <(printf '%s\n' "$2" | sort -u)
}

# --- Case 1: every name git lists is in the library's list. --------------
lib_list="$(git_local_env_vars)"
missing="$(missing_from "$runtime_list" "$lib_list")"
[ -z "$missing" ] || fail "S168 — git_local_env_vars lacks names git lists: $(tr '\n' ' ' <<<"$missing")"

# --- Case 2: the floor holds when git can't answer. ----------------------
fake="$SANDBOX/fakegit"
mkdir -p "$fake"
printf '#!/bin/sh\nexit 1\n' > "$fake/git"
chmod +x "$fake/git"
floor_failing="$(PATH="$fake:$PATH" git_local_env_vars)"
missing="$(missing_from "$runtime_list" "$floor_failing")"
[ -z "$missing" ] || fail "S168 — with a failing git, git_local_env_vars lacks: $(tr '\n' ' ' <<<"$missing")"

printf '#!/bin/sh\necho GIT_DIR\n' > "$fake/git"
floor_degraded="$(PATH="$fake:$PATH" git_local_env_vars)"
missing="$(missing_from "$runtime_list" "$floor_degraded")"
[ -z "$missing" ] || fail "S168 — with a git that lists less, git_local_env_vars lacks: $(tr '\n' ' ' <<<"$missing")"

printf '#!/bin/sh\nprintf "GIT_DIR\\nGIT_FUTURE_LOCAL_VAR\\n"\n' > "$fake/git"
future="$(PATH="$fake:$PATH" git_local_env_vars)"
assert_contains "S168 — a name only a newer git lists is included" "GIT_FUTURE_LOCAL_VAR" "$future"

# --- Case 3: nothing outside the repo-local set is listed. ---------------
for kept in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
            GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_CONFIG_SYSTEM GIT_EXEC_PATH \
            GIT_SSH GIT_SSH_COMMAND GIT_TERMINAL_PROMPT GIT_TRACE GIT_EDITOR \
            GIT_ALLOW_PROTOCOL CLAUDE_WORKFLOW_GUARDRAILS_OFF HOME PATH; do
  if grep -qx "$kept" <<<"$lib_list"; then
    fail "S168 — git_local_env_vars lists $kept, which must never be cleared"
  fi
done

# --- Case 4: clear and assert_clear do what they say. --------------------
clear_output="$(
  for v in $lib_list; do export "$v=set-by-S168"; done
  export GIT_AUTHOR_NAME="kept author" CLAUDE_WORKFLOW_GUARDRAILS_OFF=1
  git_local_env_clear
  for v in $lib_list; do
    if [ -n "${!v+x}" ]; then echo "STILL SET $v"; fi
  done
  echo "GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME-<unset>}"
  echo "CLAUDE_WORKFLOW_GUARDRAILS_OFF=${CLAUDE_WORKFLOW_GUARDRAILS_OFF-<unset>}"
  if git_local_env_assert_clear; then echo "assert_clear: ok"; fi
)"
case "$clear_output" in
  *"STILL SET"*) fail "S168 — git_local_env_clear left: $(grep 'STILL SET' <<<"$clear_output" | tr '\n' ' ')" ;;
esac
assert_contains "S168 — git_local_env_clear keeps the identity" "GIT_AUTHOR_NAME=kept author" "$clear_output"
assert_contains "S168 — git_local_env_clear keeps the guardrails override" "CLAUDE_WORKFLOW_GUARDRAILS_OFF=1" "$clear_output"
assert_contains "S168 — git_local_env_assert_clear passes after a clear" "assert_clear: ok" "$clear_output"

assert_output="$(export GIT_INDEX_FILE=/some/index; git_local_env_assert_clear 2>&1; echo "status=$?")"
case "$assert_output" in
  *status=0*) fail "S168 — git_local_env_assert_clear returned 0 with GIT_INDEX_FILE set" ;;
esac
assert_contains "S168 — git_local_env_assert_clear names the variable" "GIT_INDEX_FILE" "$assert_output"

# --- Case 5: one copy of the list (A19 "violated when"). -----------------
# A name only a hand-written copy of the list would contain.
for f in "$TEST_REPO_ROOT"/hooks/* "$TEST_REPO_ROOT"/lib/*.sh "$TEST_REPO_ROOT/test/lib.sh" \
         "$TEST_REPO_ROOT/test/run.sh" "$TEST_REPO_ROOT/check"; do
  [ -f "$f" ] || continue
  [ "$f" = "$library" ] && continue
  if grep -q 'GIT_SHALLOW_FILE\|GIT_REPLACE_REF_BASE' "$f"; then
    fail "S168 — ${f#"$TEST_REPO_ROOT"/} holds a second copy of the repo-local variable list"
  fi
done

test_done
