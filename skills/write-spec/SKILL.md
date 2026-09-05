---
name: write-spec
description: >
  Hoe werk gespecificeerd wordt: PRD.md en TEST-SCENARIOS.md bijhouden, werk
  opsplitsen in GitHub issues, en de Dekt:-conventie (tokengrammatica,
  traceability) die scenario's aan functionaliteit koppelt. Gebruik dit bij het
  opstellen van issues, PRD-secties of testscenario's.
---

## Specificeren van werk (PRD, testscenario's, issues)

1. Elk project houdt een `PRD.md` (as-built of ontwerp) en
   `TEST-SCENARIOS.md` (Given/When/Then) bij — zie `templates/` in dit
   repo voor de vorm. Bij adoptie van een nieuw project scaffold `adopt.sh`
   beide automatisch als ze nog niet bestaan.
2. Werk wordt vanuit de PRD opgesplitst in GitHub issues: één `Epic`-issue
   voor het geheel, `Work item`-issues per te bouwen onderdeel (zie
   `templates/ISSUE_TEMPLATE/`).
3. Elk work-item-issue heeft eigen Given/When/Then-acceptatiecriteria en
   verwijst naar de bijbehorende scenario's in `TEST-SCENARIOS.md` — zo is
   elk issue direct bruikbaar om de gebouwde software tegen te testen.
4. `PRD.md`/`TEST-SCENARIOS.md` zijn levende documenten: bijwerken zodra de
   implementatie ervan afwijkt (zoals nu al gebeurt in tennis-registration
   en tennis-invoicing).

Voor de onderbouwingsplicht bij het opstellen of herzien van
`PRD.md`/`ARCHITECTUUR.md` — de skill `adoption-registry`.

## Dekking vastleggen met `Dekt:`

Elk testscenario draagt een `**Dekt:**`-veld onder zijn kop, met de
functionaliteit uit `PRD.md` die het beschrijft. Komma-gescheiden bij meer dan
één. De tokenvorm is een vaste grammatica: `^[A-Z]{1,2}[0-9]+[a-z]?$` —
bijvoorbeeld `F1`, `S2` of `S2b`. Twee beginletters mag ook (`OP4`), en die
staart-letter (`S2b`) is bestaand gebruik, geen slordigheid.

Twee regels die je niet moet omzeilen. **Het prefix ligt niet vast**: `F`/`S` is
gebruikelijk, maar een project dat zijn scenario's `R`/`A`/`B`/`P` nummert werkt
ongewijzigd — de controle toetst dat een token oplost naar een bestaande kop,
niet welke letter ervoor staat. En **alleen het veld telt**: een ID dat in
lopende tekst voorkomt is geen verwijzing, anders zou elke zin die toevallig
"S1" noemt een dekking opleveren die er niet is.

`check-traceability.sh` controleert dit offline, aangeroepen vanuit het `check`
van het project. Hij is niet retroactief: zolang geen enkel scenario het veld
draagt, waarschuwt hij alleen. Maar let op wat dat betekent — zodra het eerste
veld er staat, geldt de eis voor **alle** functionaliteit in de PRD, ook voor
items die niets met dat werk te maken hebben. Vul je het veld voor het eerst in
een project met een bestaande achterstand in, doe dat dan in een PR waarin je
die achterstand ook aanpakt of bewust als schuld vastlegt.
