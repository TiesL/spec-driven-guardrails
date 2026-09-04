#!/usr/bin/env bash
# T1, T2, S30 — schakel 1 van de traceabilityketen, offline.
# Dekt: F13
#
# Het ontwerp uit W17: geen F/S hardcoderen. Verzamel ID-tokens uit de koppen
# van PRD.md en TEST-SCENARIOS.md en controleer dat elk Dekt:-token in de andere
# set oplost. Een check die op dag een faalt in een van de vier projecten, staat
# op dag twee uit - vandaar dat een PRD zonder ID's waarschuwt en niet faalt.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-traceability.sh"
[ -x "$script" ] || { fail "T1 — templates/check-traceability.sh ontbreekt of is niet uitvoerbaar"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

# Bouwt een project met de meegegeven PRD- en scenario-inhoud.
bouw() {
  local naam="$1" prd="$2" scen="$3"
  local pad="$SANDBOX/$naam"
  mkdir -p "$pad"
  printf '%s\n' "$prd" > "$pad/PRD.md"
  printf '%s\n' "$scen" > "$pad/TEST-SCENARIOS.md"
  echo "$pad"
}

# T1 — volledige keten, alles gedekt.
p="$(bouw t1 \
'## Functionaliteit

### F1 — iets' \
'### S1 — verwacht gedrag
**Dekt:** F1

### S2 — wat er misgaat
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T1 — volledige dekking gaf exit $status: $uitvoer"

# T2 — functionaliteit zonder scenario faalt, met naam.
p="$(bouw t2 \
'### F1 — gedekt

### F2 — ongedekt' \
'### S1 — iets
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T2 — ongedekte F2 gaf exit 0"
assert_contains "T2 — de melding noemt F2" "F2" "$uitvoer"

# S30 — dubbele ID's en een onbekend token, apart gemeld.
p="$(bouw s30 \
'### F1 — iets' \
'### S1 — eerste
**Dekt:** F1

### S1 — tweede, zelfde ID
**Dekt:** F1

### S2 — verwijst nergens heen
**Dekt:** F9')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S30 — dubbel ID en onbekend token gaven exit 0"
assert_contains "S30 — het dubbele ID wordt gemeld" "S1" "$uitvoer"
assert_contains "S30 — het onopgeloste token wordt gemeld" "F9" "$uitvoer"

# AC5 — een PRD zonder enig ID waarschuwt en faalt niet. tennis-invoicing is dit
# geval; faalde het script daar, dan zou het daar meteen uitgezet worden.
p="$(bouw ac5 \
'## Functionaliteit

Dit project beschrijft zijn functionaliteit in proza, zonder ID-koppen.' \
'### S1 — iets
**Dekt:**')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "AC5 — prefixloos PRD gaf exit $status in plaats van een waarschuwing"
assert_contains "AC5 — er verschijnt een waarschuwing" "waarschuwing" "$uitvoer"

# S62 — een project dat de conventie nog niet gebruikt, waarschuwt en faalt niet.
# Alle vier de bestaande projecten zijn dit geval op de dag van invoering.
p="$(bouw s62 \
'### F1 — iets

### F2 — nog iets' \
'### S1 — iets, zonder dekkingsveld
- Given: ...')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S62 — project zonder Dekt:-velden gaf exit $status in plaats van een waarschuwing"
assert_contains "S62 — er verschijnt een waarschuwing" "waarschuwing" "$uitvoer"
case "$uitvoer" in
  *F1*|*F2*) fail "S62 — het meldde alsnog ongedekte items: $uitvoer" ;;
esac

# En zodra de eerste verwijzing er staat, handhaaft hij wel — anders zou een
# project met één Dekt:-veld de rest ongestraft kunnen laten liggen.
p="$(bouw s62b \
'### F1 — gedekt

### F2 — ongedekt' \
'### S1 — iets
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S62 — met één Dekt:-veld werd F2 niet gehandhaafd"
assert_contains "S62 — F2 wordt gemeld zodra de conventie in gebruik is" "F2" "$uitvoer"

# T5 — alleen het veld telt. Een ID in lopende tekst is geen verwijzing, en een
# regel die niet met het veld begint evenmin. Zonder deze controle zou elke zin
# die per ongeluk een ID noemt een dekking opleveren die er niet is.
p="$(bouw t5 \
'### F1 — gedekt

### F2 — niet gedekt, wordt alleen in proza genoemd' \
'### S1 — iets
**Dekt:** F1
- Given: dit scenario noemt Dekt: F2 in lopende tekst, wat geen verwijzing is
- When: het script draait
- Then: F2 telt niet als gedekt')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T5 — 'Dekt: F2' in lopende tekst telde als dekking"
assert_contains "T5 — F2 blijft ongedekt" "F2" "$uitvoer"

# Prefix-agnostisch. Dit is de kern van besluit c uit W17: tennis-admin nummert
# zijn scenario's R/A/B/P en gebruikt OP voor open punten. Een script dat op F/S
# keyt, is daar op dag één onbruikbaar - en dat is met F/S-testdata alleen niet
# aan te tonen.
p="$(bouw prefixvrij \
'### R1 — een eis met een eigen prefix

### OP4 — een open punt, twee beginletters' \
'### B7 — scenario met weer een ander prefix
**Dekt:** R1

### P2b — en een met een staart-letter
**Dekt:** OP4')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "prefix-agnostisch — R/OP/B/P werd niet herkend: $uitvoer"

# En een verwijzing naar een niet-bestaand ID met eigen prefix wordt wél gemeld,
# zodat "alles goedkeuren" niet als prefix-agnostisch doorgaat.
p="$(bouw prefixvrij-fout \
'### R1 — bestaat' \
'### B7 — verwijst nergens heen
**Dekt:** R9')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "prefix-agnostisch — onbekend R9 werd niet gemeld"
assert_contains "prefix-agnostisch — R9 staat in de melding" "R9" "$uitvoer"

# Een placeholder uit het sjabloon is geen verwijzing. Een vers gescaffold
# project draagt `**Dekt:** <F1>`; faalt de controle daarop, dan staat hij bij
# het eerste gebruik al uit.
p="$(bouw placeholder \
'### F1 — iets' \
'### S1 — vers uit het sjabloon
**Dekt:** <F1>')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "placeholder — <F1> werd als verwijzing behandeld: $uitvoer"

# Een Dekt:-token met staart-letter. a2t-emails heeft een S2b, en een
# grammatica die dat afwijst is daar meteen onbruikbaar. Zonder deze zaak is
# niet aantoonbaar dat het script de staart-letter accepteert - een test met
# alleen S1/S2 laat een striktere grammatica ongemoeid.
p="$(bouw staartletter \
'### F1 — iets' \
'### S2b — een scenario met staart-letter
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "staart-letter — S2b werd niet als geldig ID herkend: $uitvoer"

p="$(bouw staartletter-fout \
'### F1 — iets

### F2 — ongedekt' \
'### S1 — verwijst naar een niet-bestaand ID met staart-letter
**Dekt:** F1, F2b')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "staart-letter — onbekend F2b werd niet gemeld"
assert_contains "staart-letter — F2b staat in de melding" "F2b" "$uitvoer"

# De andere richting: een Dekt:-veld in PRD.md verwijst naar een scenario. Beide
# richtingen worden gecontroleerd; zonder deze zaak kon de controle op de
# PRD-kant stilzwijgend weggehaald worden.
p="$(bouw andersom \
'### F1 — verwijst naar een scenario dat niet bestaat
**Dekt:** S9' \
'### S1 — iets
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "andere richting — onbekend S9 in PRD.md werd niet gemeld"
assert_contains "andere richting — S9 staat in de melding" "S9" "$uitvoer"

# Exacte match, geen substring. Zonder `grep -qx` zou een hangende verwijzing
# naar F1 stilzwijgend oplossen tegen een bestaande F123 — en dan meldt de
# controle "in orde" terwijl er nergens een F1 bestaat.
p="$(bouw substring \
'### F123 — het enige item' \
'### S1 — dekt F123
**Dekt:** F123

### S2 — hangende verwijzing die substring is van F123
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "substring — F1 loste op tegen F123"
assert_contains "substring — F1 staat in de melding" "F1" "$uitvoer"

# Een duplicaat dat niet naast zijn tweeling staat. Zonder sorteren vóór het
# zoeken naar dubbelen ziet `uniq -d` alleen aangrenzende regels, en dan glipt
# precies het realistische geval erdoor: een kopieerfout verderop in een groot
# bestand.
p="$(bouw duplicaat-uiteen \
'### F1 — iets' \
'### S1 — eerste
**Dekt:** F1

### S2 — er tussenin
**Dekt:** F1

### S1 — dezelfde ID, ver van de eerste
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "duplicaat-uiteen — niet-aangrenzend dubbel S1 werd gemist"
assert_contains "duplicaat-uiteen — S1 staat in de melding" "S1" "$uitvoer"

# Een kapot token wordt gemeld, niet stil weggefilterd. Anders belooft de
# controle dat elk token oplost terwijl hij juist de tikfouten niet ziet.
p="$(bouw kapot-token \
'### F1 — iets

### F2 — iets' \
'### S1 — met een tikfout ertussen
**Dekt:** F1, F-2, F2')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "kapot token — 'F-2' werd stil weggefilterd"
assert_contains "kapot token — F-2 staat in de melding" "F-2" "$uitvoer"

# Spaties in plaats van komma's leveren één onbruikbaar token op. Ook dat moet
# gemeld worden, want anders lijkt het veld ingevuld en dekt het niets.
p="$(bouw spatie-gescheiden \
'### F1 — iets

### F2 — iets' \
'### S1 — spaties in plaats van komma is
**Dekt:** F1 F2')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "spatie-gescheiden — 'F1 F2' werd stil weggefilterd"

test_klaar "T1/T2/T5/S30/S62"
