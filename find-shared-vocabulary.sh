#!/usr/bin/env bash
# find-shared-vocabulary.sh — Generates candidates for layer B (W33/#57, W38):
# every literal string that a script from this repo matches in a file or
# GitHub issue/PR of a different (adopted) repo. Doesn't replace human
# judgment — surfaces candidates, the curation lives in issue #110.
#
# Two parts:
#   1. Regression check: does every already-confirmed layer-B token still
#      exist where it was found? If it silently disappears (e.g. through a
#      refactor), this inventory itself is out of date.
#   2. Candidate scan: greps the same scripts for new combinations of a
#      project_dir-like variable and a literal, quoted string after it —
#      possible new layer-B candidates not covered by part 1.
#
# Usage: ./find-shared-vocabulary.sh
# Re-run whenever adopt.sh, pending-changes.sh, the skills/pre-merge-review
# scripts, templates/check-*.sh, hooks/git-guardrails, or lib/*.sh change.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$eigen_map"

fout=0

echo "=== Deel 1: regressiecontrole op bevestigde laag-B-tokens ==="

controleer() {
  local omschrijving="$1" bestand="$2" patroon="$3"
  if [ ! -f "$bestand" ]; then
    echo "MIST: $omschrijving — $bestand bestaat niet meer" >&2
    fout=1
    return
  fi
  if grep -qE -- "$patroon" "$bestand"; then
    echo "ok — $omschrijving ($bestand)"
  else
    echo "MIST: $omschrijving — patroon niet meer gevonden in $bestand" >&2
    fout=1
  fi
}

controleer "WORKFLOW-ADOPTIE.md als bestandsnaam" pending-changes.sh 'WORKFLOW-ADOPTIE\.md'
controleer "ja/nee-antwoordwaarden (seed)" adopt.sh '\| ja \|'
controleer "de stempel 'vereist onderbouwing'" pending-changes.sh 'vereist onderbouwing'
controleer ".gitignore-beheerde-blokmarkering" adopt.sh 'claude-workflow: begin'
controleer "issue-templates (cp -f)" adopt.sh 'cp -f "\$template_src"'
controleer "entry-ID proces-context-document als logica-gate" adopt.sh 'proces-context-document'
controleer "entry-ID kwaliteitsreview-voor-merge als logica-gate" hooks/git-guardrails 'kwaliteitsreview-voor-merge'
controleer "het \\*\\*Dekt:\\*\\*-veld (project-eigen PRD/TEST-SCENARIOS)" templates/check-traceability.sh 'Dekt:'
controleer "het \\*\\*Dekt:\\*\\*-veld (externe issue-bodies)" skills/pre-merge-review/scenario-poort.sh 'Dekt:'
controleer "de <!-- nfr: <id> -->-anker" lib/nfr.sh 'nfr: \$id'
controleer "de <!-- pre-merge-review:done -->-marker (externe PR-comments)" hooks/git-guardrails 'pre-merge-review:done'

echo
echo "=== Deel 2: kandidatenscan (nieuwe combinaties, handmatig te beoordelen) ==="

kandidaat_scripts="adopt.sh pending-changes.sh hooks/git-guardrails lib/changes.sh lib/nfr.sh skills/pre-merge-review/scope.sh skills/pre-merge-review/scenario-poort.sh templates/check-traceability.sh templates/check-pr-issue-link.sh templates/check-main-via-pr.sh"

for script in $kandidaat_scripts; do
  [ -f "$script" ] || continue
  # Lines with a project_dir/antwoorden/prd/scenarios-like variable followed
  # by grep/case on a quoted string — the shape every layer-B token found so
  # far shares.
  treffers="$(grep -nE '\$(project_dir|antwoorden|prd|scenarios)' "$script" \
    | grep -E "grep |case |==|~" \
    | grep -vE '^\s*#')"
  if [ -n "$treffers" ]; then
    echo "--- $script ---"
    echo "$treffers"
  fi
done

echo
if [ "$fout" -eq 0 ]; then
  echo "find-shared-vocabulary.sh: alle bevestigde laag-B-tokens nog aanwezig."
else
  echo "find-shared-vocabulary.sh: inventaris is verouderd — zie MIST hierboven." >&2
fi
exit "$fout"
