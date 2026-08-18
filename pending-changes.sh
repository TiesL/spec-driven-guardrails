#!/usr/bin/env bash
# pending-changes.sh — Meldt welke adopteerbare wijzigingen uit CHANGES.md nog
# geen antwoord hebben in WORKFLOW-ADOPTIE.md van een project.
#
# Gebruik:
#   ./pending-changes.sh [/pad/naar/project]   # standaard: huidige directory
#
# Wordt aangeroepen door de SessionStart-hook (zie settings/session-hooks.json).
# Print niets wanneer er niets openstaat, en eindigt altijd met exit 0 — een
# hook mag een sessie nooit blokkeren.
#
# Een wijziging staat open wanneer haar "Van toepassing als"-predicaat waar is
# én er geen rij voor dat ID in WORKFLOW-ADOPTIE.md staat. De afwezigheid van
# een rij betekent dus "nog niet van toepassing geweest": wordt de conditie later
# alsnog waar, dan duikt de vraag vanzelf op.

set -uo pipefail

workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${1:-.}" 2>/dev/null && pwd)" || exit 0
changes="$workflow_dir/CHANGES.md"
antwoorden="$project_dir/WORKFLOW-ADOPTIE.md"

[ -f "$changes" ] || exit 0

# Predicaten. Uitgedrukt als case-statement in plaats van eval van vrije tekst
# uit CHANGES.md: voorspelbaar, en een typefout levert "onbekend" op in plaats
# van een onbedoeld commando.
van_toepassing() {
  case "$1" in
    altijd)
      return 0 ;;
    heeft-package-json)
      [ -f "$project_dir/package.json" ] ;;
    heeft-deploy-script)
      [ -f "$project_dir/package.json" ] &&
        grep -q '"deploy"[[:space:]]*:' "$project_dir/package.json" ;;
    *)
      return 1 ;;
  esac
}

beantwoord() {
  [ -f "$antwoorden" ] && grep -q "^| *$1 *|" "$antwoorden"
}

openstaand=()
huidig_id=""
while IFS= read -r regel; do
  case "$regel" in
    '## '*)
      huidig_id="${regel#\#\# }" ;;
    *'**Van toepassing als:**'*)
      predicaat="${regel##*\*\* }"
      predicaat="$(echo "$predicaat" | tr -d '[:space:]')"
      if [ -n "$huidig_id" ] && van_toepassing "$predicaat" && ! beantwoord "$huidig_id"; then
        openstaand+=("$huidig_id")
      fi ;;
  esac
done < "$changes"

if [ ${#openstaand[@]} -gt 0 ]; then
  echo "Openstaande workflow-wijzigingen voor dit project (zie CHANGES.md in claude-workflow):"
  for id in "${openstaand[@]}"; do
    vraag="$(awk -v id="## $id" '
      $0 == id { in_entry = 1; next }
      in_entry && /\*\*Vraag:\*\*/ {
        sub(/.*\*\*Vraag:\*\* */, ""); print; exit
      }
      in_entry && /^## / { exit }
    ' "$changes")"
    echo "  - $id — $vraag"
  done
  echo "Leg per wijziging een ja/nee-antwoord vast in WORKFLOW-ADOPTIE.md."
fi

# Loopt de lokale checkout achter, dan is bovenstaande lijst mogelijk
# onvolledig. Alleen melden, niet zelf pullen — een hook hoort niets te muteren.
if git -C "$workflow_dir" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  achter="$(git -C "$workflow_dir" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "${achter:-0}" -gt 0 ]; then
    echo "Let op: claude-workflow loopt $achter commit(s) achter op origin/main — draai daar 'git pull'."
  fi
fi

exit 0
