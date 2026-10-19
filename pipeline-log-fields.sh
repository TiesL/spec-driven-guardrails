#!/usr/bin/env bash
# pipeline-log-fields.sh — Read-only check of one issue's Pipeline log for
# dispatch-economy fields (issue #532, A42, rules OR22/OR23).
#
# Usage:
#   ./pipeline-log-fields.sh <issue-number>
#
# A dispatch line is a Pipeline log line that carries `agent=<id>` and
# `model=<m>`. OR22 asks it to also carry `continued=yes|no`, `rule=<OR13|OR46>`
# and the size the dispatch result reported, `tokens=<n>[k|m]` and
# `tools=<n>`. This script prints one line per problem:
#   line <n> (agent=<id>): missing <field>
#   line <n> (agent=<id>): reported size over the limit without a reason
# "Over the limit" = more than 150k tokens or more than 100 tool uses reported
# (the flag threshold of OR23; a proxy for the transcript-based flag in
# skills/dispatch-economy). A `reason="..."` on a line of the same agent id
# clears it; a reason on another agent id does not. Lines without `agent=` and
# `model=` (an OR46 command-and-result line, the heading) are not dispatch
# lines.
#
# It reports and never blocks: exit 0 whether or not it found problems, and
# also when the log cannot be read (a warning says so), the same posture as the
# other read-only reporters (A33a: the log is a recorded self-check, not
# proof). Exit 2 only for a usage error.
#
# Needs `gh` (REST only, one call) with this project's checkout as the working
# directory; with several git remotes run `gh repo set-default` first.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail
export LC_ALL=C  # GitHub text is read as bytes (A32c)

if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: pipeline-log-fields.sh <issue-number>" >&2
  exit 2
fi
case "$1" in
  *[!0-9]*|0)
    echo "usage: pipeline-log-fields.sh <issue-number> (must be a positive integer)" >&2
    exit 2
    ;;
esac
issue="$1"

warn() { echo "pipeline-log-fields: warning: $1" >&2; }

if ! command -v gh >/dev/null 2>&1; then
  warn "gh not found, could not read the Pipeline log of issue $issue."
  exit 0
fi

body="$(gh api "repos/{owner}/{repo}/issues/$issue/comments" --paginate \
  --jq '.[] | select((.body // "") | test("^\\s*#*\\s*Pipeline log")) | .body' 2>/dev/null)"
status=$?
if [ "$status" -ne 0 ]; then
  warn "gh failed, could not read the Pipeline log of issue $issue."
  exit 0
fi
if [ -z "$body" ]; then
  warn "no Pipeline log comment found on issue $issue, could not read any dispatch line."
  exit 0
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/pipeline-log-fields.XXXXXX")" || { warn "no temp file, could not read the Pipeline log."; exit 0; }
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$body" > "$tmp"

awk '
function get(l, k) {
  if (match(l, " " k "=[^ \t,;)]+")) return substr(l, RSTART + length(k) + 2, RLENGTH - length(k) - 2)
  return ""
}
function num(v) {
  v = tolower(v); gsub(",", "", v)
  if (v ~ /m$/) { sub(/m$/, "", v); return v * 1000000 }
  if (v ~ /k$/) { sub(/k$/, "", v); return v * 1000 }
  return v + 0
}
function reason(l) { return (l ~ /[ \t]reason=("[^"]+"|[^ \t"]+)/) }
NR == FNR {
  l = " " $0
  id = get(l, "agent")
  if (id != "" && reason(l)) has_reason[id] = 1
  next
}
{
  l = " " $0
  id = get(l, "agent")
  if (id == "" || get(l, "model") == "") next
  c = get(l, "continued"); r = get(l, "rule"); t = get(l, "tokens"); u = get(l, "tools")
  if (c == "") print "line " FNR " (agent=" id "): missing continued"
  else if (c != "yes" && c != "no") print "line " FNR " (agent=" id "): continued must be yes or no"
  if (r == "") print "line " FNR " (agent=" id "): missing rule"
  if (t == "" || u == "") print "line " FNR " (agent=" id "): missing reported size (tokens and tools)"
  else if ((num(t) > 150000 || num(u) > 100) && !(id in has_reason))
    print "line " FNR " (agent=" id "): reported size over the limit without a reason"
}
' "$tmp" "$tmp"
exit 0
