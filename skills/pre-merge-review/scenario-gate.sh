#!/usr/bin/env bash
# skills/pre-merge-review/scenario-gate.sh — Link 2 (scenario -> issue) as
# a gate in pre-merge-review (W20, F13 decision d).
#
# Usage:
#   scenario-gate.sh <project_dir>
#
# For every scenario ID from <project_dir>/TEST-SCENARIOS.md: is it named
# in the **Covers:** field of at least one issue (open or closed)? Only
# that field counts — same grammar and same "only the field counts" rule
# as templates/check-traceability.sh (link 1), applied here to issues
# instead of to PRD.md/TEST-SCENARIOS.md against each other. An ID that
# happens to appear in a sentence is not a reference.
#
# W42/#114: issue bodies match both **Covers:** and the pre-migration
# **Dekt:** field, permanently — unlike PRD.md/TEST-SCENARIOS.md (which get
# a real cutover), a historical, possibly already-closed issue is not
# something this migration rewrites. Confirmed with Ties.
#
# Fail-open without gh or network: warn, don't block — same ground rule as
# the deploy-guards and the merge guard (W10b).
#
# Output on stdout: one line per uncovered scenario:
#   "<id> is covered by no issue (link 2)"
#
# No `eval`. TEST-SCENARIOS.md and issue text aren't fully under their own
# control. Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

project_dir="${1:?usage: scenario-gate.sh <project_dir>}"
scenarios="$project_dir/TEST-SCENARIOS.md"

[ -f "$scenarios" ] || exit 0

# Same regex as check-traceability.sh's ids_from_headings: only headings
# count, the prefix isn't fixed (F/S is customary, R/A/B/P/OP occur).
scenario_ids="$(grep -oE '^#+[[:space:]]+[A-Z]{1,2}[0-9]+[a-z]?([[:space:]]|$)' "$scenarios" \
  | sed 's/^#*[[:space:]]*//; s/[[:space:]]*$//')"
[ -n "$scenario_ids" ] || exit 0

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: scenario-gate can't find gh and is skipping link 2." >&2
  exit 0
fi

issuebodies="$(gh issue list --state all --limit 500 --json body --jq '.[].body' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: scenario-gate couldn't consult issues (no network or no access) and is skipping link 2." >&2
  echo "$issuebodies" >&2
  exit 0
fi

# Same shape as covers_raw/covers_tokens in check-traceability.sh: only the
# **Covers:** field at the start of a line counts, comma-separated. Also
# matches the pre-migration **Dekt:** field (permanent exception, see
# above) — hence the alternation in the grep patterns below.
gedekt="$(printf '%s\n' "$issuebodies" \
  | grep -E '^\*\*(Covers|Dekt):\*\*' \
  | sed 's/^\*\*Covers:\*\*[[:space:]]*//; s/^\*\*Dekt:\*\*[[:space:]]*//' \
  | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | grep -v '^$' \
  | sort -u)"

printf '%s\n' "$scenario_ids" | while IFS= read -r id; do
  [ -n "$id" ] || continue
  if ! printf '%s\n' "$gedekt" | grep -qxF "$id"; then
    echo "$id is covered by no issue (link 2)"
  fi
done
