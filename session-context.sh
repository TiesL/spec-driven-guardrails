#!/usr/bin/env bash
# session-context.sh — #371 A16: what a session in this project must load
# that nothing else loads.
#
# Usage:
#   ./session-context.sh [--runtime claude|codex] [--slot <n>] [/path/to/project]
#   # defaults: Claude/current directory; Codex explicitly reads the output
#
# --slot <n> (#499, A41): the output is split at each marker line
# `<!-- session-context: slot -->` (a declared file may hold one), the
# marker lines are dropped and only chunk n (1-based) is printed. Each
# SessionStart command prints one chunk, so each hook output stays within
# CONTEXT_BUDGET_CHARS (lib/context-budget.sh, checked by S309): slot 1 is
# the CLAUDE.md warning plus part 1 of ORCHESTRATOR.md, slot 2 is part 2. A
# slot past the last chunk prints nothing. Without --slot every chunk is
# printed in order with the marker lines dropped (what Codex reads).
#
# Called by the SessionStart hook (settings/session-hooks.json), after
# pending-changes.sh, with the clone resolved through the project's
# .claude/settings.json symlink. Whatever it prints becomes session
# context. Two jobs:
#
# 1. For every CHANGES.md entry this project answered yes (answered_yes,
#    lib/changes.sh) whose **Reaches session:** field declares
#    `session-context: <path>`, print that file verbatim (minus marker lines,
#    see --slot). A `no`,
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
# Default Claude hook invocation exits 0: a hook must never block a session.
# Invalid runtime/options exit 2 before context reads. A declared file that
# is missing warns on stderr and prints nothing for it.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

runtime=claude
slot=""
if [ "${1:-}" = --runtime ]; then
  [ "$#" -ge 2 ] || { echo "session-context: missing runtime" >&2; exit 2; }
  runtime="$2"; shift 2
fi
case "$runtime" in claude|codex) ;; *) echo "session-context: unknown runtime" >&2; exit 2 ;; esac
if [ "${1:-}" = --slot ]; then
  [ "$#" -ge 2 ] || { echo "session-context: missing slot" >&2; exit 2; }
  slot="$2"; shift 2
  case "$slot" in
    ''|*[!0-9]*|0*) echo "session-context: slot must be a positive integer" >&2; exit 2 ;;
  esac
fi
[ "$#" -le 1 ] || { echo "session-context: invalid arguments" >&2; exit 2; }
case "${1:-}" in -*) echo "session-context: invalid option" >&2; exit 2 ;; esac

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

emit() {
if [ "$runtime" = codex ]; then
  if ! python3 "$workflow_dir/lib/codex-adoption.py" "$workflow_dir" "$project_dir" status >/dev/null 2>&1; then
    echo "Warning: Codex AGENTS.md/links installation is missing, stale or conflicting; run adopt.sh --runtime codex again and verify actual instruction loading."
  fi
  echo "runtime-hooks: not-installed; runtime shell interception unavailable"
else
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

fi

[ -f "$changes" ] || return 0

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

}

# The marker line splits chunks; it is never printed.
marker='<!-- session-context: slot -->'
emit | awk -v m="$marker" -v n="${slot:-0}" '
  $0 == m { chunk++; next }
  n == 0 || chunk == n - 1 { print }
'
exit 0
