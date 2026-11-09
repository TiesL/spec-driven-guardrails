#!/usr/bin/env bash
# merge-risk-evidence.sh — read-only evidence check for the merge-risk panel
# (#646, A58 D4). It never merges, labels, comments or votes.
#
# Usage (run from the project's checkout, so gh resolves the project's repo):
#   merge-risk-evidence.sh [--phase class|final] <pr-number>   (default final)
#   merge-risk-evidence.sh --queue
#
# Stdout, first line:
#   merge-risk: <eligible|held|referred|unresolved> pr=<n> head=<H> base=<B> diff=<sha256> config=<C>
# then one `reason: <code> <detail>` line per reason (all of them, stable
# codes, listed in skills/merge-risk-panel/SKILL.md) and `note:` lines.
# The configuration is policy/merge-autonomy.json read at the current `main`
# tip, never at the candidate head. merge-preflight.sh runs with the guard's
# escape hatches removed from its environment.
#
# Exit codes: 0 eligible, 1 held, 3 referred, 4 unresolved, 2 usage. A caller
# reads any other exit, a crash, or missing gh/python3 as unresolved. The
# verifier binds only when it is run and obeyed; nothing here intercepts
# `gh pr merge`.
#
# All logic lives in the private lib/merge-risk.py; this wrapper parses flags
# and checks that its tools exist.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

usage() { echo "usage: merge-risk-evidence.sh [--phase class|final] <pr-number> | --queue" >&2; }

phase=final have_phase=0 queue=0 pr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      if [ $# -lt 2 ] || [ "$have_phase" -eq 1 ]; then usage; exit 2; fi
      case "$2" in class | final) phase="$2" ;; *) usage; exit 2 ;; esac
      have_phase=1
      shift 2
      ;;
    --queue)
      [ "$queue" -eq 0 ] || { usage; exit 2; }
      queue=1
      shift
      ;;
    '' | *[!0-9]* | 0*)
      usage
      exit 2
      ;;
    *)
      [ -z "$pr" ] || { usage; exit 2; }
      pr="$1"
      shift
      ;;
  esac
done
if [ "$queue" -eq 1 ]; then
  if [ -n "$pr" ] || [ "$have_phase" -eq 1 ]; then usage; exit 2; fi
elif [ -z "$pr" ]; then
  usage
  exit 2
fi

unresolved() {
  printf 'merge-risk: unresolved pr=%s head=- base=- diff=- config=-\nreason: %s\n' "${pr:--}" "$1"
  exit 4
}

command -v python3 >/dev/null 2>&1 || unresolved "python3-missing nothing was checked"
command -v gh >/dev/null 2>&1 || unresolved "gh-missing nothing was checked"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || unresolved "verifier-missing script directory"
[ -r "$script_dir/lib/merge-risk.py" ] || unresolved "verifier-missing lib/merge-risk.py"

if [ "$queue" -eq 1 ]; then
  python3 -I "$script_dir/lib/merge-risk.py" collect-queue
else
  python3 -I "$script_dir/lib/merge-risk.py" collect --phase "$phase" "$pr" "$script_dir"
fi
rc=$?
case "$rc" in
  0 | 1 | 3 | 4) exit "$rc" ;;
  *) unresolved "verifier-crash exit=$rc" ;;
esac
