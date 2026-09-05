#!/usr/bin/env bash
# skills/pre-merge-review/scope.sh — Berekent de reviewscope voor de
# `pre-merge-review`-skill (W13, F11).
#
# Gebruik:
#   scope.sh <project_dir> [workflow_dir]
#
# <workflow_dir> is de map met lib/nfr.sh en nfr/ — standaard afgeleid uit de
# eigen locatie van dit script (twee mappen omhoog), zodat het ook werkt
# wanneer dit script via de per-skill symlink in een geadopteerd project
# draait. Handig om te overriden in tests.
#
# complexiteit en dependencies horen altijd bij de scope (basishygiëne, F11),
# ongeacht welke NFR's dit project koos. Daarnaast: elke spec-*-rij in
# <project_dir>/WORKFLOW-ADOPTIE.md die met "ja" begint — dat is zowel een
# definitief "ja" als de voorlopige stempel "ja — vereist onderbouwing" die
# adopt.sh zet (F6). Die laatste vorm blijft zichtbaar gemarkeerd in de
# uitvoer: de skill behandelt zo'n rij als reviewbevinding (de eerste poort
# van F6), en dat kan alleen als de scope het onderscheid niet wegveegt.
#
# Per zo'n rij wordt het anker `<!-- nfr: <id> -->` in <project_dir>/PRD.md
# opgezocht; de ###-kop direct erboven levert de leesbare naam. Ontbreekt het
# anker (project zonder het door F4 geplaatste blok, of een PRD.md die er nog
# niet is), dan valt de scope terug op de kopnaam uit het NFR-register zelf en
# meldt dat expliciet op stderr — degraderen, niet blokkeren (S27).
#
# Uitvoer op stdout: één scope-item per regel — "complexiteit", "dependencies",
# dan per beantwoorde NFR "<id>: <kopnaam>", optioneel gevolgd door
# " [vereist onderbouwing]".
#
# Geen `eval`: WORKFLOW-ADOPTIE.md en PRD.md zijn tekst die niet volledig onder
# eigen beheer staat.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

set -uo pipefail

project_dir="${1:?gebruik: scope.sh <project_dir> [workflow_dir]}"

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
workflow_dir="${2:-$(cd "$eigen_map/../.." && pwd)}"

# shellcheck source=../../lib/nfr.sh
. "$workflow_dir/lib/nfr.sh"

antwoorden="$project_dir/WORKFLOW-ADOPTIE.md"
prd="$project_dir/PRD.md"

echo "complexiteit"
echo "dependencies"

[ -f "$antwoorden" ] || exit 0

# ID + volledig antwoord (getrimd) van elke spec-*-rij die met "ja" begint,
# tab-gescheiden zodat het antwoord zelf spaties mag bevatten.
ja_rijen="$(awk -F'|' '
  /^\| *spec-[a-z-]+ *\|/ {
    id = $2; gsub(/^[ \t]+|[ \t]+$/, "", id)
    antwoord = $3; gsub(/^[ \t]+|[ \t]+$/, "", antwoord)
    if (antwoord == "ja" || antwoord ~ /^ja[^a-zA-Z]/) {
      print id "\t" antwoord
    }
  }
' "$antwoorden")"

[ -n "$ja_rijen" ] || exit 0

while IFS=$'\t' read -r id antwoord; do
  [ -n "$id" ] || continue

  kop=""
  if [ -f "$prd" ]; then
    kop="$(awk -v anker="<!-- nfr: $id -->" '
      /^### / { kop = $0; sub(/^### /, "", kop) }
      $0 == anker { print kop; exit }
    ' "$prd")"
  fi

  if [ -z "$kop" ]; then
    echo "waarschuwing: anker voor $id ontbreekt in ${prd#"$project_dir"/} — teruggevallen op de kopnaam uit het NFR-register" >&2
    kop="$(nfr_veld "$workflow_dir/nfr/$id.md" kop)"
    [ -n "$kop" ] || kop="$id"
  fi

  if [ "$antwoord" = "ja" ]; then
    echo "$id: $kop"
  else
    echo "$id: $kop [vereist onderbouwing]"
  fi
done <<EOF
$ja_rijen
EOF
