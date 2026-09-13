#!/usr/bin/env bash
# skills/pre-merge-review/scope.sh — Computes the review scope for the
# `pre-merge-review` skill (W13, F11).
#
# Usage:
#   scope.sh <project_dir> [workflow_dir]
#
# <workflow_dir> is the directory with lib/nfr.sh and nfr/ — by default
# derived from this script's own location (two directories up), so it also
# works when this script runs via the per-skill symlink in an adopted
# project. Handy to override in tests.
#
# Complexity and dependencies always belong in the scope (basic hygiene,
# F11), regardless of which NFRs this project chose. On top of that: every
# spec-* row in <project_dir>/WORKFLOW-ADOPTION.md whose Answer is exactly
# "yes" (adoption-registry's format: the Answer column is always
# literally "yes"/"ja" or "no"/"nee", never more text). adopt.sh doesn't put
# F6's provisional stamp in that column, but in the Notes: "at
# adoption — requires substantiation during ..." (see seed_entry() in
# adopt.sh). A yes-row whose whole line contains the text "requires
# substantiation" therefore stays visibly flagged in the output — same grep
# shape pending-changes.sh already uses to recognize that signal — and the
# skill treats such a row as a review finding (F6's first gate).
#
# For each such row, the anchor `<!-- nfr: <id> -->` is looked up in
# <project_dir>/PRD.md; the `###` heading directly above it gives the
# readable name. If the anchor is missing (a project without the block F4
# places, or a PRD.md that doesn't exist yet), the scope falls back to the
# heading name from the NFR register itself and reports that explicitly on
# stderr — degrade, don't block (S27).
#
# Output on stdout: one scope item per line — "complexity", "dependencies",
# then per answered NFR "<id>: <heading name>", optionally followed by
# " [requires substantiation]".
#
# No `eval`: WORKFLOW-ADOPTION.md and PRD.md are text that isn't fully
# under its own control.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

project_dir="${1:?usage: scope.sh <project_dir> [workflow_dir]}"

own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
workflow_dir="${2:-$(cd "$own_dir/../.." && pwd)}"

# shellcheck source=../../lib/nfr.sh
. "$workflow_dir/lib/nfr.sh"

# W42/#114: the new filename takes priority; the pre-migration filename is
# still read so scope still works for a project that hasn't migrated yet
# (pending-changes.sh is what flags that migration, not this script).
#
# Deliberately accepts *both* "yes" and "ja" as the affirmative value,
# regardless of which filename was found — not filename-determined. A
# project can rename WORKFLOW-ADOPTIE.md to WORKFLOW-ADOPTION.md without,
# in the same step, having converted every row's ja/nee to yes/no (the
# migration notice lists the rename before the value change). Picking the
# expected value from the filename alone would then silently produce an
# empty NFR scope — no warning, review looks clean, nothing was actually
# checked.
answers="$project_dir/WORKFLOW-ADOPTION.md"
[ -f "$answers" ] || answers="$project_dir/WORKFLOW-ADOPTIE.md"
prd="$project_dir/PRD.md"

echo "complexity"
echo "dependencies"

[ -f "$answers" ] || exit 0

# IDs of every spec-* row whose Answer is exactly "yes" or "ja".
yes_ids="$(awk -F'|' '
  /^\| *spec-[a-z-]+ *\|/ {
    id = $2; gsub(/^[ \t]+|[ \t]+$/, "", id)
    answer = $3; gsub(/^[ \t]+|[ \t]+$/, "", answer)
    if (answer == "yes" || answer == "ja") print id
  }
' "$answers")"

[ -n "$yes_ids" ] || exit 0

while IFS= read -r id; do
  [ -n "$id" ] || continue

  heading=""
  if [ -f "$prd" ]; then
    heading="$(awk -v anchor="<!-- nfr: $id -->" '
      /^### / { heading = $0; sub(/^### /, "", heading) }
      $0 == anchor { print heading; exit }
    ' "$prd")"
  fi

  if [ -z "$heading" ]; then
    echo "warning: anchor for $id is missing from ${prd#"$project_dir"/} — falling back to the heading name from the NFR register" >&2
    heading="$(nfr_field "$workflow_dir/nfr/$id.md" heading)"
    # #156: $id may be a pre-rename ID still recorded in this project's
    # WORKFLOW-ADOPTION.md — nfr/ no longer has a file under that name,
    # so retry under the current one before giving up on a heading.
    [ -n "$heading" ] || heading="$(nfr_field "$workflow_dir/nfr/$(nfr_current_id "$id").md" heading)"
    [ -n "$heading" ] || heading="$id"
  fi

  # Same grep shape as pending-changes.sh: the whole row counts, since the
  # provisional stamp lives in Notes, not in Answer.
  row="$(grep -m1 "^| *$id *|" "$answers")"
  case "$row" in
    *"vereist onderbouwing"*|*"requires substantiation"*) echo "$id: $heading [requires substantiation]" ;;
    *) echo "$id: $heading" ;;
  esac
done <<EOF
$yes_ids
EOF
