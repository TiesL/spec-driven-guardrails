#!/usr/bin/env bash
# skills/pre-merge-review/scenario-poort.sh — Schakel 2 (scenario -> issue) als
# poort in pre-merge-review (W20, F13 besluit d).
#
# Gebruik:
#   scenario-poort.sh <project_dir>
#
# Voor elk scenario-ID uit <project_dir>/TEST-SCENARIOS.md: wordt het genoemd
# in het **Dekt:**-veld van minstens één issue (open of dicht)? Alleen dat
# veld telt — dezelfde grammatica en dezelfde "alleen het veld telt"-regel als
# templates/check-traceability.sh (schakel 1), hier toegepast op issues in
# plaats van op PRD.md/TEST-SCENARIOS.md onderling. Een ID dat toevallig in
# een zin voorkomt is geen verwijzing.
#
# Faal-open zonder gh of netwerk: waarschuwen, niet blokkeren — dezelfde
# grondregel als de deploy-guards en de merge-guard (W10b).
#
# Uitvoer op stdout: één regel per ongedekt scenario:
#   "<id> wordt door geen enkel issue gedekt (schakel 2)"
#
# Geen `eval`. TEST-SCENARIOS.md en issue-teksten zijn tekst die niet volledig
# onder eigen beheer staat. Bash 3.2-compatibel: geen declare -A, geen
# mapfile, geen ${var,,}.

set -uo pipefail

project_dir="${1:?gebruik: scenario-poort.sh <project_dir>}"
scenarios="$project_dir/TEST-SCENARIOS.md"

[ -f "$scenarios" ] || exit 0

# Zelfde regex als check-traceability.sh's ids_uit_koppen: alleen koppen
# tellen, prefix ligt niet vast (F/S is gebruikelijk, R/A/B/P/OP komen voor).
scenario_ids="$(grep -oE '^#+[[:space:]]+[A-Z]{1,2}[0-9]+[a-z]?([[:space:]]|$)' "$scenarios" \
  | sed 's/^#*[[:space:]]*//; s/[[:space:]]*$//')"
[ -n "$scenario_ids" ] || exit 0

if ! command -v gh >/dev/null 2>&1; then
  echo "waarschuwing: scenario-poort vindt gh niet en slaat schakel 2 over." >&2
  exit 0
fi

issuebodies="$(gh issue list --state all --limit 500 --json body --jq '.[].body' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "waarschuwing: scenario-poort kon issues niet raadplegen (geen netwerk of geen toegang) en slaat schakel 2 over." >&2
  echo "$issuebodies" >&2
  exit 0
fi

# Zelfde vorm als dekt_ruw/dekt_tokens in check-traceability.sh: alleen het
# **Dekt:**-veld aan regelbegin telt, komma-gescheiden.
gedekt="$(printf '%s\n' "$issuebodies" \
  | grep '^\*\*Dekt:\*\*' \
  | sed 's/^\*\*Dekt:\*\*[[:space:]]*//' \
  | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | grep -v '^$' \
  | sort -u)"

printf '%s\n' "$scenario_ids" | while IFS= read -r id; do
  [ -n "$id" ] || continue
  if ! printf '%s\n' "$gedekt" | grep -qxF "$id"; then
    echo "$id wordt door geen enkel issue gedekt (schakel 2)"
  fi
done
