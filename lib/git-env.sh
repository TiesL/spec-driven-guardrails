#!/usr/bin/env bash
# lib/git-env.sh — Isolation from git's repo-local environment (A19, #377).
#
# Source, don't execute. git exports repo-local variables (GIT_DIR,
# GIT_INDEX_FILE, GIT_PREFIX, ...) to every hook, `git rebase --exec`
# command and `!` alias. A child that then runs `git -C <fixture> ...`
# acts on the launching repo instead of the fixture: it moves real
# branches, adds tags, sets core.bare=true or writes into the real index.
# Two callers clear these variables through this one seam: hooks/pre-commit
# (for the ./check child only) and test/lib.sh (when sourced).
#
# The list is the union of `git rev-parse --local-env-vars`, read at
# runtime so a newer git's additions are covered, and a fixed floor, so a
# git that fails or lists fewer never clears less. Nothing outside this
# list is touched: the git identity, GIT_CONFIG_GLOBAL/NOSYSTEM, GIT_SSH*,
# GIT_TRACE*, GIT_EDITOR and CLAUDE_WORKFLOW_GUARDRAILS_OFF all survive.
# This is the only copy of the list (A19 "violated when").
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# The fixed floor: what git 2.50 prints for `git rev-parse --local-env-vars`.
GIT_LOCAL_ENV_FLOOR="GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS
GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE
GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX
GIT_SHALLOW_FILE GIT_COMMON_DIR"

# Prints every repo-local variable name, one per line, without duplicates.
git_local_env_vars() {
  {
    # shellcheck disable=SC2086  # word-splitting the floor is the point
    printf '%s\n' $GIT_LOCAL_ENV_FLOOR
    git rev-parse --local-env-vars 2>/dev/null
  } | awk '/^[A-Za-z_][A-Za-z0-9_]*$/ && !seen[$0]++'
}

# Unsets every name git_local_env_vars prints, in the current shell.
git_local_env_clear() {
  local _git_env_name
  for _git_env_name in $(git_local_env_vars); do
    unset "$_git_env_name"
  done
}

# Returns non-zero, naming the first repo-local variable still set.
git_local_env_assert_clear() {
  local _git_env_name
  for _git_env_name in $(git_local_env_vars); do
    if [ -n "${!_git_env_name+x}" ]; then
      echo "$_git_env_name is set (value '${!_git_env_name}')" >&2
      return 1
    fi
  done
  return 0
}
