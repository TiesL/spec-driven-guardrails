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

# shellcheck source=lib/changes.sh
. "$workflow_dir/lib/changes.sh"
# shellcheck source=lib/nfr.sh
. "$workflow_dir/lib/nfr.sh"
antwoorden="$project_dir/WORKFLOW-ADOPTIE.md"

[ -f "$changes" ] || exit 0

# shellcheck disable=SC2329  # aangeroepen vanuit verzamel_openstaand
beantwoord() {
  [ -f "$antwoorden" ] && grep -q "^| *$1 *|" "$antwoorden"
}

openstaand=()

# Callback voor itereer_entries. `standaard` blijft hier bewust ongebruikt: een
# onbeantwoorde vraag staat open ongeacht of hij `ja` of `vraag` als startpunt
# had. adopt.sh doet met datzelfde veld juist wél iets — zie de callback daar.
# shellcheck disable=SC2329  # indirect aangeroepen, via itereer_entries
verzamel_openstaand() {
  local id="$1" predicaat="$3"
  if predicaat_waar "$predicaat" "$project_dir" && ! beantwoord "$id"; then
    openstaand+=("$id")
  fi
}

itereer_alle_entries "$workflow_dir" verzamel_openstaand

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
    # Staat het ID niet in CHANGES.md, dan komt hij uit het NFR-register.
    if [ -z "$vraag" ]; then
      vraag="$(nfr_vraag "$workflow_dir/nfr" "$id")"
    fi
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
