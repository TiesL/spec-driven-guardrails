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

# Een geseede rij is nog geen besluit. adopt.sh zet elke van toepassing zijnde
# `Standaard: ja`-wijziging op "ja — vereist onderbouwing": een voorlopige
# stempel. beantwoord() ziet alleen dát er een rij staat, nooit wat erin staat,
# dus zonder dit signaal meldt een vers geadopteerd project niets openstaand
# terwijl er zeventien voorlopige stempels liggen.
#
# beantwoord() wordt daarvoor bewust niet aangepast: dat zou de openstaand-set
# veranderen en daarmee R9 breken, de regressietest die bewaakt dat geen enkel
# project ooit een vraag opnieuw krijgt. Dit staat er dus náást.
#
# Gefaseerd onderbouwen is het uitgangspunt (zie F6): niet alles ineens, maar
# bij eerste aanraking van het onderwerp. Dit is poort 3 — het signaal blijft
# zichtbaar tot een rij echt beantwoord is.
if [ -f "$antwoorden" ]; then
  # Geen `|| echo 0`: grep -c print zélf al "0" bij nul treffers, en geeft
  # daarnaast exitstatus 1. Die twee samen leveren de string "0\n0" op, waar de
  # vergelijking hieronder op stukloopt. De ${wachtend:-0}-fallback dekt het
  # geval dat grep helemaal niets naar stdout schrijft, bijvoorbeeld bij
  # ontbrekende leesrechten.
  #
  # Alleen tabelrijen tellen mee, net als beantwoord() dat op de ID-kolom
  # ankert: een losse notitie boven of onder de tabel die toevallig dezelfde
  # woorden bevat, is geen wachtende onderbouwing.
  wachtend="$(grep -c '^|.*vereist onderbouwing' "$antwoorden" 2>/dev/null)"
  if [ "${wachtend:-0}" -gt 0 ]; then
    echo "$wachtend rij(en) in WORKFLOW-ADOPTIE.md wachten nog op onderbouwing."
    echo "Vervang de voorlopige stempel door een op dit project gegronde redenering,"
    echo "of zet de rij om naar 'nee' met reden — bij het onderwerp waar je toch al zit."
  fi
fi

# Mist het project skills die dit repo wél heeft, dan is de adoptie verouderd.
#
# LET OP: deze melding adviseert `adopt.sh` opnieuw te draaien. Dat helpt pas
# zodra adopt.sh skills daadwerkelijk installeert — dat landt in W8 (#20). Tot
# die tijd is de hele controle een no-op, want `skills/` bestaat nog niet. Voeg
# die map dus niet toe vóór W8, anders adviseert dit een reparatie die niets
# doet.
# Wat gesymlinkt is (WORKFLOW.md, de hookconfiguratie) is na een `git pull`
# direct actief; wat adopt.sh installeert loopt achter tot iemand hem opnieuw
# draait. Zonder deze melding houdt een project stilzwijgend de oude wereld.
if [ -d "$workflow_dir/skills" ]; then
  ontbrekend=""
  for skill_pad in "$workflow_dir"/skills/*/; do
    [ -d "$skill_pad" ] || continue
    skill="$(basename "$skill_pad")"
    if [ ! -e "$project_dir/.claude/skills/$skill" ]; then
      # Komma-gescheiden: een skillnaam met een spatie erin zou anders niet te
      # onderscheiden zijn van meerdere losse namen.
      if [ -n "$ontbrekend" ]; then
        ontbrekend="$ontbrekend, $skill"
      else
        ontbrekend="$skill"
      fi
    fi
  done
  if [ -n "$ontbrekend" ]; then
    echo "Dit project mist de skill(s): $ontbrekend."
    echo "Draai adopt.sh opnieuw vanuit claude-workflow om ze te installeren."
  fi
fi

# Staat main uitgecheckt, dan is dat het moment waarop vertakken nog gratis is
# (W23, F18/S54/S55). De commit-blokkade in hooks/git-guardrails grijpt pas
# wanneer er al werk is — Edit, Write, git add en git stash gaan allemaal door
# op main. Puur informatief: geen mutatie, geen blokkade, exit 0 en niets op
# stderr, dezelfde eis als het onderbouwingssignaal hierboven (S43).
if branch="$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null)" \
  && [ "$branch" = "main" ]; then
  echo "Je zit op main. Nieuw werk hoort op een eigen branch:"
  echo "  git checkout -b feature/<naam>"
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
