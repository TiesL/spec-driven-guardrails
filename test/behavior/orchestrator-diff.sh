#!/usr/bin/env bash
# orchestrator-diff.sh — differential run of the orchestrator behavior scenarios (#499, A41, AC12)
#
# Compares skills/role-contracts/ORCHESTRATOR.md at --base (default origin/main)
# with the working tree's, scenario by scenario, N runs per arm, through
# `claude -p` (or the stub named by CLAUDE_BIN). Costs money: the real claude is
# only started here. Not run by ./check or CI.
#
# Usage: test/behavior/orchestrator-diff.sh [--base <rev>] [--runs N] [--model M]
#          [--max-budget-usd X] [--calibrate] [--baseline] [--mutant-rule ORn]
#          [--repo <dir>]
#   (default)    old (base) against new (working tree); exit 0 only when every
#                scenario is `same` or `changed-as-intended`, and then writes
#                test/behavior/orchestrator-diff.stamp.
#   --baseline   old against old: passes when every unlisted scenario is `same`.
#   --calibrate  old against old (noise floor) plus a mutant arm that must
#                come out `diverged`. --mutant-rule picks the rule whose
#                first never/not is removed (default OR43, whose removal
#                flips meaning; OR40's only never is redundant, #499).
# Exit: 0 pass, 1 verdicts fail, 2 usage/input error, 3 budget cap reached.
#
# Bash 3.2-compatible. No `timeout` (macOS has none).

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "orchestrator-diff: python3 is required" >&2; exit 2; }
repo=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 || { echo "orchestrator-diff: --repo needs a value" >&2; exit 2; } ;;
    *) args+=("$1"); shift ;;
  esac
done
[ -n "$repo" ] || repo="$(cd "$here/../.." && pwd)"
exec python3 -I "$here/orchestrator_diff.py" run --repo "$repo" ${args[@]+"${args[@]}"}
