#!/usr/bin/env bash
# S60 — Acceptatiecriteria in het sjabloon heten AC<n>.
# Dekt: F13
#
# Zolang een issue zijn eigen criteria `S1` noemt, raakt elke grep naar
# scenarioverwijzingen het issue zelf. Schakel 2 (scenario -> issue) is dan niet
# controleerbaar: elk issue lijkt naar elk scenario te verwijzen.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sjabloon="$TEST_REPO_ROOT/templates/ISSUE_TEMPLATE/work-item.md"

# Given: het sjabloon voor een work item.
[ -f "$sjabloon" ] || { fail "S60 — work-item.md ontbreekt"; test_klaar; }

# Then: de criteria zijn AC<n> genummerd.
grep -qE '^#+ +AC[0-9]+' "$sjabloon" \
  || fail "S60 — geen AC<n>-genummerd acceptatiecriterium in work-item.md"

# And: geen eigen S<n>-nummering meer. Een kop als `### S1:` is de nummering;
# `S2b` in lopende tekst is een verwijzing en mag blijven. Het onderscheid zit
# in de kop, niet in het voorkomen van de letter.
eigen_nummering="$(grep -nE '^#+ +S[0-9]+' "$sjabloon" || true)"
[ -z "$eigen_nummering" ] \
  || fail "S60 — work-item.md nummert nog zelf met S<n>: $eigen_nummering"

# And: het sjabloon draagt het dekkingsveld, aan regelbegin.
grep -q '^\*\*Dekt:\*\*' "$sjabloon" \
  || fail "S60 — work-item.md heeft geen '**Dekt:**' aan regelbegin"

# And: **Dekt:** staat tussen Epic en Blocked by. Dat is geen smaak: elk bestaand
# issue in dit repo schrijft die volgorde, en een sjabloon dat een andere volgorde
# voordoet levert twee schrijfwijzen op waarvan er straks één per ongeluk de norm
# wordt.
volgorde="$(grep -nE '^\*\*(Epic|Dekt|Blocked by|Blocks):\*\*' "$sjabloon" | sed 's/^[0-9]*://; s/:\*\*.*/:**/' | tr '\n' ' ')"
verwacht="**Epic:** **Dekt:** **Blocked by:** **Blocks:** "
[ "$volgorde" = "$verwacht" ] \
  || fail "S60 — veldvolgorde is '$volgorde', verwacht '$verwacht'"

# And: de losse regels die Dekt vervangt zijn weg. Blijven ze staan, dan zijn er
# twee manieren om hetzelfde op te schrijven en raadt niemand welke telt.
for oud in "PRD-sectie" "TEST-SCENARIOS.md-scenario"; do
  grep -q "^$oud" "$sjabloon" \
    && fail "S60 — '$oud' staat er nog naast **Dekt:**"
done

test_klaar "S60"
