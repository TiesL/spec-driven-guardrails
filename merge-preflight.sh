#!/usr/bin/env bash
# merge-preflight.sh — Runs the merge guard's checks for `gh pr merge <n>`
# before the merge, for a runtime that has no hook interception (Codex,
# A44 2a). It builds the PreToolUse hook JSON for that command and pipes it
# to hooks/git-guardrails, the same code the Claude hook runs: up-to-date,
# review marker, CI and role-play checks, with the same fail-open warnings.
#
# Usage:
#   ./merge-preflight.sh <pr-number>
#
# Exit code and both streams are the guard's, unchanged: 2 with the reason on
# stderr means do not merge. Instruction-driven, not interception: a session
# can skip it, and it never merges anything itself. The guard's escape hatch
# is honored the way the guard takes it: with CLAUDE_WORKFLOW_MERGE_GUARD_OFF
# set to a non-empty value in the environment, the synthesized command carries
# the `CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1` prefix and the guard reports the
# skip loudly. Its intended use is as an invocation prefix:
# `CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 ./merge-preflight.sh <pr-number>`.
#
# The guard is found next to this script (hooks/git-guardrails), like the
# other root helpers find lib/. PR number only: a branch name is a usage
# error here (the guard resolves branch targets, this wrapper stays shallow).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

usage() { echo "usage: merge-preflight.sh <pr-number> (a positive integer)" >&2; }

if [ $# -ne 1 ]; then usage; exit 2; fi
case "$1" in
  ''|*[!0-9]*|0*) usage; exit 2 ;;
esac
pr_number="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
guard="$script_dir/hooks/git-guardrails"
if [ ! -x "$guard" ]; then
  echo "merge-preflight: hooks/git-guardrails not found next to this script — nothing was checked." >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "merge-preflight: python3 is missing — nothing was checked." >&2
  exit 2
fi

command_text="gh pr merge $pr_number"
[ -n "${CLAUDE_WORKFLOW_MERGE_GUARD_OFF:-}" ] && command_text="CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 $command_text"

json="$(PREFLIGHT_COMMAND="$command_text" python3 -I -c '
import json, os
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "cwd": os.getcwd(),
                  "tool_input": {"command": os.environ["PREFLIGHT_COMMAND"]}}))')" || {
  echo "merge-preflight: could not build the hook input — nothing was checked." >&2
  exit 2
}

printf '%s' "$json" | "$guard"
