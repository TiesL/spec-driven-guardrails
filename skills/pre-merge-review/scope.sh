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

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
workflow_dir="${2:-$(cd "$eigen_map/../.." && pwd)}"

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
antwoorden="$project_dir/WORKFLOW-ADOPTION.md"
[ -f "$antwoorden" ] || antwoorden="$project_dir/WORKFLOW-ADOPTIE.md"
prd="$project_dir/PRD.md"

echo "complexity"
echo "dependencies"

[ -f "$antwoorden" ] || exit 0

# IDs of every spec-* row whose Answer is exactly "yes" or "ja".
ja_ids="$(awk -F'|' '
  /^\| *spec-[a-z-]+ *\|/ {
    id = $2; gsub(/^[ \t]+|[ \t]+$/, "", id)
    antwoord = $3; gsub(/^[ \t]+|[ \t]+$/, "", antwoord)
    if (antwoord == "yes" || antwoord == "ja") print id
  }
' "$antwoorden")"

[ -n "$ja_ids" ] || exit 0

while IFS= read -r id; do
  [ -n "$id" ] || continue

  kop=""
  if [ -f "$prd" ]; then
    kop="$(awk -v anker="<!-- nfr: $id -->" '
      /^### / { kop = $0; sub(/^### /, "", kop) }
      $0 == anker { print kop; exit }
    ' "$prd")"
  fi

  if [ -z "$kop" ]; then
    echo "warning: anchor for $id is missing from ${prd#"$project_dir"/} — falling back to the heading name from the NFR register" >&2
    kop="$(nfr_veld "$workflow_dir/nfr/$id.md" heading)"
    [ -n "$kop" ] || kop="$id"
  fi

  # Same grep shape as pending-changes.sh: the whole row counts, since the
  # provisional stamp lives in Notes, not in Answer.
  regel="$(grep -m1 "^| *$id *|" "$antwoorden")"
  case "$regel" in
    *"vereist onderbouwing"*|*"requires substantiation"*) echo "$id: $kop [requires substantiation]" ;;
    *) echo "$id: $kop" ;;
  esac
done <<EOF
$ja_ids
EOF
