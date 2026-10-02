#!/usr/bin/env bash
# session-context.sh — #371 A16: what a session in this project must load
# that nothing else loads.
#
# Usage:
#   ./session-context.sh [/path/to/project]   # default: current directory
#
# Called by the SessionStart hook (settings/session-hooks.json), after
# pending-changes.sh, with the clone resolved through the project's
# .claude/settings.json symlink. Whatever it prints becomes session
# context. Two jobs:
#
# 1. For every CHANGES.md entry this project answered yes (answered_yes,
#    lib/changes.sh) whose **Reaches session:** field declares
#    `session-context: <path>`, print that file verbatim. A `no`,
#    unanswered or not-applicable row prints nothing: that is AC3 by
#    construction, not a rule a session has to remember. Today the one such
#    file is skills/role-contracts/ORCHESTRATOR.md
#    (process-multi-agent-roles).
# 2. Warn when the project's CLAUDE.md is not a symlink to this clone's
#    WORKFLOW.md (#371 F1): then the session doesn't load the shared
#    workflow at all, and nothing else says so.
#
# The file is read from this clone on every run, so a later release reaches
# the project's next session without re-running adopt.sh (AC11).
#
# Always exits 0: a hook must never block a session. A declared file that
# is missing warns on stderr and prints nothing for it.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${1:-.}" 2>/dev/null && pwd)" || exit 0
changes="$workflow_dir/CHANGES.md"

# shellcheck source=lib/changes.sh
. "$workflow_dir/lib/changes.sh" || exit 0

# physical <path>: the path with its directory resolved physically (pwd -P),
# so /var vs /private/var or a symlinked clone compare equal. Empty when the
# directory doesn't exist.
physical() {
  local dir
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 0
  printf '%s/%s' "$dir" "$(basename "$1")"
}

claude_md="$project_dir/CLAUDE.md"
expected="$(physical "$workflow_dir/WORKFLOW.md")"
actual=""
if [ -L "$claude_md" ]; then
  link="$(readlink "$claude_md")"
  case "$link" in
    /*) ;;
    *) link="$project_dir/$link" ;;
  esac
  actual="$(physical "$link")"
fi
if [ -z "$actual" ] || [ "$actual" != "$expected" ]; then
  echo "Warning: CLAUDE.md in $project_dir is not a link to $workflow_dir/WORKFLOW.md, so this session doesn't load the shared workflow. Run adopt.sh again from the guardrails clone to restore it."
fi

[ -f "$changes" ] || exit 0

printed=""
while IFS='|' read -r id value _; do
  case "$value" in
    session-context:*) ;;
    *) continue ;;
  esac
  file="${value#session-context:}"
  file="$(printf '%s' "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$file" ] || continue
  answered_yes "$project_dir" "$id" || continue
  if [ ! -f "$workflow_dir/$file" ]; then
    echo "warning: session-context.sh: $id declares $file, which doesn't exist in $workflow_dir" >&2
    continue
  fi
  case "$printed" in
    *"|$file|"*) continue ;;
  esac
  printed="$printed|$file|"
  echo
  cat "$workflow_dir/$file"
done < <(reaches_session_values "$changes")

exit 0
