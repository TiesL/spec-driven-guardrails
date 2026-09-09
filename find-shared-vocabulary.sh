#!/usr/bin/env bash
# find-shared-vocabulary.sh — Genereert kandidaten voor laag B (W33/#57, W38):
# elke letterlijke string die een script uit dit repo matcht in een bestand
# of GitHub-issue/PR van een ánder (geadopteerd) repo. Vervangt geen
# menselijk oordeel — surfaced kandidaten, de curatie staat in issue #110.
#
# Twee delen:
#   1. Regressiecontrole: bestaat elk al-bevestigd laag-B-token nog op de
#      plek waar het gevonden werd? Verdwijnt hij stilzwijgend (bijvoorbeeld
#      door een refactor), dan is deze inventaris zelf verouderd.
#   2. Kandidatenscan: grept dezelfde scripts op nieuwe combinaties van een
#      project_dir-achtige variabele en een letterlijke, gequote string
#      erna — mogelijke nieuwe laag-B-kandidaten die niet in deel 1 staan.
#
# Gebruik: ./find-shared-vocabulary.sh
# Draai opnieuw zodra adopt.sh, pending-changes.sh, de skills/pre-merge-review-
# scripts, templates/check-*.sh, hooks/git-guardrails of lib/*.sh wijzigen.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

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
  # Regels met een project_dir/antwoorden/prd/scenarios-achtige variabele
  # gevolgd door grep/case op een gequote string — de vorm die elk al
  # gevonden laag-B-token deelt.
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
