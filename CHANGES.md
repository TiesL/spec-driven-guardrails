# Adopteerbare wijzigingen

Elke PR op dit repo die iets toevoegt waarover een project een eigen keuze moet
maken, voegt hier één entry toe. Zonder entry stelt de voorziening in de
projecten geen vraag en denk je ten onrechte dat je gedekt bent — zie
"Adoptieregistratie" in `WORKFLOW.md`.

Per entry:

- **Vraag** — gesloten, met ja/nee te beantwoorden. Houd hem op één regel:
  `pending-changes.sh` toont alleen die eerste regel.
- **Standaard** — `ja` (in het algemeen wenselijk, tenzij een project een
  reden heeft om af te wijken) of `vraag` (geen algemene voorkeur, hangt af
  van het project). Dit is Ties' eigen voorkeur per onderwerp, niet een
  afgeleide categorie. Bepaalt alleen het startpunt: `adopt.sh` seedt
  `ja`-entries bij adoptie met een voorlopige stempel; `vraag`-entries seeden
  nooit. **Geen van beide betekent stilzwijgend accepteren** — zie de
  onderbouwingsstap in "Specificeren van werk" in `WORKFLOW.md`: `ja`-rijen
  moeten bij het opstellen van `PRD.md`/`ARCHITECTUUR.md` alsnog objectief
  onderbouwd worden (of omgezet naar `nee`), `vraag`-rijen krijgen een
  beargumenteerd voorstel in plaats van een blanco vraag.
- **Van toepassing als** — één van de predicaten uit `lib/changes.sh`, de
  bibliotheek die `adopt.sh` en `pending-changes.sh` allebei sourcen. Die lijst
  staat daar en niet hier: een derde kopie in proza loopt vroeg of laat uit de
  pas met de code. De conditie wordt elke sessie opnieuw geëvalueerd, zodat een
  wijziging alsnog opduikt zodra hij relevant wordt voor een project.
- **Ja betekent** — wat er concreet gebeurt bij een `ja`.

Het ID is de kop (`##`). Verander een bestaand ID nooit **als het al door
een project beantwoord is** — projecten verwijzen ernaar in hun
`WORKFLOW-ADOPTIE.md`, en een hernoeming laat de vraag daar opnieuw opduiken.
Een entry die nog nergens beantwoord is, mag wél herzien of vervangen worden;
controleer dat met `grep` over alle `WORKFLOW-ADOPTIE.md`'s voordat je dat
doet.

**Sectiescheidingen** zijn `###`, entries `##`. Dat onderscheid is niet
cosmetisch: de parser leest elke `## `-kop als entry, dus een kopje op dat
niveau zou een naamloze entry worden.

**Naamgeving.** Het prefix `spec-` is gereserveerd voor de vijftien NFR's —
één per subsectie onder *Niet-functionele kenmerken* in `templates/PRD.md`,
en niets anders. De reviewreikwijdte in `WORKFLOW.md` keyt op dat prefix, dus
een niet-NFR die `spec-` heet zou daar ten onrechte in meegesleept worden.
Procesafspraken krijgen `proces-`, testniveaus `test-`.

**Een entry retireren.** Haal hem uit dit bestand. Nooit ergens beantwoord?
Dan gewoon verwijderen — controleer dat met een `grep` over alle
`WORKFLOW-ADOPTIE.md`-bestanden. Wél ergens beantwoord? Dan verhuizen naar
`CHANGES-ARCHIEF.md`, met het ID ongewijzigd en een expliciete reden, zodat een
project kan nazoeken waar zijn rij vandaan komt. Zie dat bestand voor de
volledige procedure.

Laat de entry níét inert achter door alleen de velden weg te laten: sinds de
sectiescheidingen `###` zijn, is een `## `-kop hier onvoorwaardelijk een entry,
en waarschuwt de gedeelde parser als er geen `Van toepassing als` bij staat.

---

## ci-conventie

- **Vraag:** Moet dit project de CI-conventie volgen (CI roept alleen `check` aan, geen losse checks in de workflow-YAML)?
- **Standaard:** ja
- **Van toepassing als:** heeft-package-json
- **Ja betekent:** het project heeft een `check`-script dat typecheck, lint,
  tests en build omvat, en een CI-workflow die uitsluitend dát script aanroept.
  `adopt.sh` scaffoldt `templates/ci.yml` als er nog geen workflow is; een eigen,
  uitgebreidere workflow mag, zolang die de conventie volgt.
- **PR:** https://github.com/TiesL/claude-workflow/pull/2

## deploy-guards

- **Vraag:** Moet dit project de deploy-guards toepassen?
- **Standaard:** ja
- **Van toepassing als:** heeft-deploy-script
- **Ja betekent:** het deployscript weigert te draaien vanuit een ongeverifieerde
  toestand, met de voorwaarden per doelomgeving uit "Testen en deployen
  automatiseren" in `WORKFLOW.md`. Is dat nog niet zo, maak er dan een work item
  voor.
- **PR:** https://github.com/TiesL/claude-workflow/pull/3

## ci-op-pr-en-main

- **Vraag:** Moet de CI van dit project draaien op pull requests én op pushes naar `main`?
- **Standaard:** ja
- **Van toepassing als:** heeft-package-json
- **Ja betekent:** de workflow heeft zowel een `pull_request`-trigger als
  `push: branches: [main]`. Het verschil met alleen een push op de branch is
  wezenlijk: `pull_request` beoordeelt het samengevoegde resultaat, dus het geval
  waarin twee los groene branches samen breken, en het is de vorm die als
  vereiste controle op een pull request ingesteld kan worden. De push-trigger is
  de achtervang voor wat `main` langs een andere weg bereikt. Dit staat los van
  `ci-conventie`: dát antwoord gaat over wát de workflow doet (alleen `check`
  aanroepen), dit over wannéér hij draait. Een project dat het eerste al
  beantwoordde, is over het tweede nooit iets gevraagd.

  Twee dingen om te weten voor je "ja" antwoordt. Ten eerste vervalt de
  validatie van een push naar een feature-branch waar nog geen pull request bij
  hoort: het eerste CI-signaal komt dan pas bij het openen van de PR. Dat is de
  prijs voor het beoordelen van het samengevoegde resultaat, en in een workflow
  waarin de PR vroeg opengaat is die klein. Ten tweede erft deze vraag het
  bereik van `heeft-package-json`: een project met een CI-workflow maar zonder
  `package.json` krijgt hem niet, net als bij `ci-conventie`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/50

---

### Proces en ontwerpdiepte

## proces-prd

- **Vraag:** Houdt dit project een `PRD.md` bij als normatieve specificatie?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` bestaat en wordt actueel gehouden (as-built of ontwerp) — zie `templates/PRD.md`.

## architectuurdocument

- **Vraag:** Moet dit project zijn architectuurbesluiten vastleggen in `ARCHITECTUUR.md`?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** structurele keuzes (platform, lagen, eigenaarschap van gegevens, substantiële dependencies) worden vastgelegd met criteria, afgewogen opties, het besluit, de architectuureisen die eruit volgen, en wanneer de keuze herzien zou moeten worden. `adopt.sh` scaffoldt het sjabloon.

## proces-issue-tracking

- **Vraag:** Splitst dit project werk op in GitHub-issues (epics/work items)?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `adopt.sh` ververst `.github/ISSUE_TEMPLATE/`, en werk wordt vanuit de PRD opgesplitst in een `Epic`-issue met `Work item`-issues — zie `templates/ISSUE_TEMPLATE/`.

## test-unit

- **Vraag:** Heeft dit project unittests voor de kernlogica?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** de kernlogica (idealiter een domeinlaag zonder externe afhankelijkheden — zie `spec-testability`) heeft unittests, en `check` draait ze.

## test-feature-gwt

- **Vraag:** Beschrijft dit project functionaliteit als Given/When/Then-scenario's?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `TEST-SCENARIOS.md` bestaat en dekt elk functionaliteitsitem uit de PRD met minstens één Given/When/Then-scenario voor het verwachte gedrag — zie `templates/TEST-SCENARIOS.md`. De faalscenario's daarnaast vallen onder `spec-failure-modes`.

## test-integratie

- **Vraag:** Heeft dit project geautomatiseerde integratietests (over componentgrenzen heen, tegen een echte of gesimuleerde externe afhankelijkheid)?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** naast unittests bestaan er tests die de samenwerking tussen componenten (of met een extern platform) verifiëren, en `check` draait ze — of een expliciete reden waarom dat voor dit project niet proportioneel is.

## kwaliteitsreview-voor-merge

- **Vraag:** Moet elke PR in dit project vóór de merge een kwaliteitsreview krijgen, met de bevindingen in de PR?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** vóór de merge draait een review met verse context en op een ander model dan dat de code schreef. De review checkt altijd complexiteit en dependencies (basishygiëne), plus precies de NFR's waarvoor de bijbehorende `spec-*`-vraag in dit project met "ja" is beantwoord. Bevindingen komen in de PR; elke bevinding wordt opgelost of vastgelegd onder *Technical debt* in de PRD.

## proces-technical-debt-register

- **Vraag:** Houdt dit project een apart Technical debt-register bij naast Bekende beperkingen?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` scheidt *Bekende beperkingen* (blijft zo) van *Technical debt* (per regel: waarom nu acceptabel, en de trigger om het aan te pakken) — beide subsecties staan al in het sjabloon.

## proces-refactoring-triggers

- **Vraag:** Gelden de refactoring-triggers uit `WORKFLOW.md` voor dit project?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** een work item dat het vastgelegde ontwerp zou schenden, wordt niet via een omweg toch gebouwd — dat is het signaal voor een eigen herontwerp-work-item. Zie "Complexiteit, technical debt en refactoring" in `WORKFLOW.md`. De eerste trigger veronderstelt een vastgelegd ontwerp; heeft dit project geen `ARCHITECTUUR.md` (zie `architectuurdocument`), dan gelden alleen de tweede en derde trigger.

---

### Niet-functionele kenmerken (NFR's)

De vijftien niet-functionele kenmerken staan niet hier maar in `nfr/` — één
bestand per kenmerk, met de vraag, wat "ja" betekent en de invulhulp bij elkaar.
Ze stonden eerder zowel hier als in `templates/PRD.md` en moesten met de hand
synchroon blijven; nu zijn beide consument van datzelfde register.

De scripts lezen `CHANGES.md` én `nfr/`, dus voor een project verandert er
niets: dezelfde vragen, op dezelfde momenten. Retirement gaat daar via het veld
`status: geretireerd` in plaats van een verhuizing naar het archief.
