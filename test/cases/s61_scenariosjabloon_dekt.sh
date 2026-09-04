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
#
# De controle onthoudt de vórige regel in plaats van vooruit te kijken. Een
# vooruitkijkende variant verliest een kop zodra er direct een nieuwe op volgt -
# dan slaat het kop-patroon toe vóór de controle op de vorige kop kan draaien -
# en ziet de laatste kop van het bestand nooit, want daar komt geen regel meer
# achter. Beide gevallen leverden groen op terwijl het veld ontbrak.
ontbreekt="$(awk '
  vorige_kop != "" && $0 !~ /^\*\*Dekt:\*\*/ { print vorige_kop }
  { vorige_kop = "" }
  /^### [A-Z]{1,2}[0-9]+[a-z]?( |$)/ { vorige_kop = $2 }
  END { if (vorige_kop != "") print vorige_kop }
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

# And: het veld toont een placeholder, geen verzonnen ID. Een sjabloon met een
# echt ogend `F3` nodigt uit om dat over te nemen, en dan verwijst het eerste
# scenario van elk nieuw project naar functionaliteit die er niet is.
verzonnen="$(grep '^\*\*Dekt:\*\*' "$sjabloon" | grep -v '<' || true)"
[ -z "$verzonnen" ] \
  || fail "S61 — **Dekt:** zonder placeholder: $(printf '%s' "$verzonnen" | tr '\n' ' ')"

test_klaar "S61"
