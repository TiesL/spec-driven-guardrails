#!/usr/bin/env bash
# S61 — Het scenariosjabloon draagt het dekkingsveld en de grammatica.
# Dekt: F13
#
# Een sjabloon dat de vorm voordoet zonder hem te benoemen leert de uitzondering
# niet aan. Dan strandt de eerste `S2b` op een handhaving die niemand had zien
# aankomen - en a2t-emails heeft die S2b vandaag al.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sjabloon="$TEST_REPO_ROOT/templates/TEST-SCENARIOS.md"
[ -f "$sjabloon" ] || { fail "S61 — templates/TEST-SCENARIOS.md ontbreekt"; test_klaar; }

# Then: elk voorbeeldscenario toont een **Dekt:**-veld direct onder zijn kop.
ontbreekt="$(awk '
  /^### [A-Z]{1,2}[0-9]+[a-z]?( |$)/ { kop = $2; verwacht = NR + 1; next }
  verwacht && NR == verwacht {
    if ($0 !~ /^\*\*Dekt:\*\*/) print kop
    verwacht = 0
  }
' "$sjabloon")"
[ -z "$ontbreekt" ] \
  || fail "S61 — scenario's zonder **Dekt:** direct onder de kop: $(echo "$ontbreekt" | tr '\n' ' ')"

# And: er is minstens één voorbeeldscenario, anders is de controle hierboven leeg
# en groen tegelijk.
aantal="$(grep -cE '^### [A-Z]{1,2}[0-9]+[a-z]?( |$)' "$sjabloon")"
[ "$aantal" -ge 1 ] \
  || fail "S61 — geen enkel voorbeeldscenario in het sjabloon"

# And: élke scenariokop draagt een ID. Alleen tellen wat een ID heeft laat een
# kop zónder ID ongemoeid, en dan doet het sjabloon precies voor wat de
# conventie verbiedt.
zonder_id="$(grep -E '^### ' "$sjabloon" | grep -vE '^### [A-Z]{1,2}[0-9]+[a-z]?( |$)' || true)"
[ -z "$zonder_id" ] \
  || fail "S61 — scenariokop zonder ID: $(printf '%s' "$zonder_id" | tr '\n' ' ')"

# And: de grammatica staat er expliciet, met S2b als voorbeeld.
grep -q '\^\[A-Z\]{1,2}\[0-9\]+\[a-z\]?\$' "$sjabloon" \
  || fail "S61 — de tokengrammatica staat niet letterlijk in het sjabloon"
grep -q 'S2b' "$sjabloon" \
  || fail "S61 — S2b staat niet als voorbeeld bij de grammatica"

test_klaar "S61"
