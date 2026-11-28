#!/usr/bin/env bash
# session-context.sh — #371 A16: what a session in this project must load
# that nothing else loads.
#
# Usage:
#   ./session-context.sh [--runtime claude|codex] [/path/to/project]
#   # defaults: Claude/current directory; Codex explicitly reads the output
#
# Called by the one session-context SessionStart command
# (settings/session-hooks.json), after pending-changes.sh, with the clone
# resolved through the project's .claude/settings.json symlink. Whatever it
# prints becomes session context, so it prints no rule text (#750, A66 D2):
# an `opt-in-loaded:` file (today skills/role-contracts/ORCHESTRATOR.md,
# process-multi-agent-roles) reaches the session as always-loaded
# instructions that adopt.sh installs, not through this hook. Jobs:
#
# 1. Claude runtime: warn when the project's CLAUDE.md is not a symlink to
#    this clone's WORKFLOW.md (#371 F1): then the session doesn't load the
#    shared workflow at all, and nothing else says so.
# 2. Claude runtime: one warning line, without rule text, when the core
#    link .claude/rules/sdg-orchestrator-core.md disagrees with the answer:
#    opted in and the link is missing or doesn't resolve to the file
#    process-multi-agent-roles declares `opt-in-loaded:` in this clone; or
#    not opted in and the link is still there (A66 D2, D5).
# 3. Claude runtime only: warn in one fixed line when the main session looks
#    routed through a proxy (#707, see main_session_routed below).
# 4. Codex runtime: the adoption status warning (stale or missing install,
#    including the core block and instructions-over-limit) and its hook and
#    bundle lines.
#
# Exits 0: a hook must never block a session. Invalid runtime/options
# (including the retired --slot) exit 2 before context reads.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

runtime=claude
if [ "${1:-}" = --runtime ]; then
  [ "$#" -ge 2 ] || { echo "session-context: missing runtime" >&2; exit 2; }
  runtime="$2"; shift 2
fi
case "$runtime" in claude|codex) ;; *) echo "session-context: unknown runtime" >&2; exit 2 ;; esac
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

# #707 (A61, AC9): the main Claude session must talk to its provider directly
# (Remote Control needs that); only children launched through route-child.sh
# are routed. Routed means ANTHROPIC_BASE_URL is set to anything but exactly
# the first-party URL, in the inherited environment or in the user or project
# settings env read directly (whether hook processes see settings env is
# unverified). The managed-settings file is not read. One fixed line, no path
# or value, printed once; an unreadable or odd file adds nothing (fail open).
FIRST_PARTY_URL="https://api.anthropic.com"
ROUTED_WARNING="Warning: ANTHROPIC_BASE_URL routes this session away from api.anthropic.com (shell or settings env); Remote Control needs it direct. SDG never sets it."
main_session_routed() {
  if [ "${ANTHROPIC_BASE_URL+set}" = set ] && [ "$ANTHROPIC_BASE_URL" != "$FIRST_PARTY_URL" ]; then
    return 0
  fi
  python3 -I -c '
import json, sys
first_party = sys.argv[1]
for path in sys.argv[2:]:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        continue
    env = data.get("env") if isinstance(data, dict) else None
    if isinstance(env, dict) and "ANTHROPIC_BASE_URL" in env and env["ANTHROPIC_BASE_URL"] != first_party:
        sys.exit(0)
sys.exit(1)
' "$FIRST_PARTY_URL" "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json" \
    "$project_dir/.claude/settings.json" "$project_dir/.claude/settings.local.json" 2>/dev/null
}

# The core file process-multi-agent-roles declares `opt-in-loaded:`, and
# whether this project answered it yes (the shared reader, A66 D3).
core_rel="$(opt_in_loaded_path "$changes" process-multi-agent-roles)"
opt_in_core=""
if [ -n "$core_rel" ] && answered_yes "$project_dir" process-multi-agent-roles; then
  opt_in_core="$core_rel"
fi

# core_link_warning: A66 D2's one line. No rule text, no rule ID.
CORE_LINK=".claude/rules/sdg-orchestrator-core.md"
core_link_warning() {
  [ -n "$core_rel" ] || return 0
  local link="$project_dir/$CORE_LINK" target
  if [ -n "$opt_in_core" ]; then
    if [ -L "$link" ] && [ -e "$link" ]; then
      target="$(readlink "$link")"
      case "$target" in /*) ;; *) target="$(dirname "$link")/$target" ;; esac
      [ "$(physical "$target")" = "$(physical "$workflow_dir/$core_rel")" ] && return 0
    fi
    echo "Warning: this project answered process-multi-agent-roles yes, but $CORE_LINK is missing or not a link to $workflow_dir/$core_rel, so this session doesn't load the orchestrator core. Run adopt.sh again from the guardrails clone to restore it."
  elif [ -L "$link" ]; then
    echo "Warning: $CORE_LINK still loads the orchestrator core, but this project has not answered process-multi-agent-roles yes. Run adopt.sh again from the guardrails clone to remove it."
  fi
}

emit() {
if [ "$runtime" = codex ]; then
  codex_inventory="$(SDG_OPT_IN_CORE="$opt_in_core" PYTHONDONTWRITEBYTECODE=1 python3 "$workflow_dir/lib/codex-adoption.py" "$workflow_dir" "$project_dir" status 2>&1)"
  if [ "$?" -ne 0 ]; then
    echo "Warning: Codex installation is missing, stale, conflicting or recovery pending; run adopt.sh --runtime codex again and verify actual instruction loading."
  fi
  printf '%s\n' "$codex_inventory" | sed -n '/^runtime-hooks:/p; /^guard bundle:/p; /^Refresh must /p; /^pending:/p'
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
if main_session_routed; then
  echo "$ROUTED_WARNING"
fi
core_link_warning
fi
}

emit
exit 0
