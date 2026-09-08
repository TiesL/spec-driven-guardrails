# Adopteerbare wijzigingen

Elke PR op dit repo die iets toevoegt waarover een project een eigen keuze moet
maken, voegt hier één entry toe. Zonder entry stelt de voorziening in de
projecten geen vraag en denk je ten onrechte dat je gedekt bent — zie
de skill `adoption-registry`.

Per entry:

- **Vraag** — gesloten, met ja/nee te beantwoorden. Houd hem op één regel:
  `pending-changes.sh` toont alleen die eerste regel.
- **Standaard** — `ja` (in het algemeen wenselijk, tenzij een project een
  reden heeft om af te wijken) of `vraag` (geen algemene voorkeur, hangt af
  van het project). Dit is Ties' eigen voorkeur per onderwerp, niet een
  afgeleide categorie. Bepaalt alleen het startpunt: `adopt.sh` seedt
  `ja`-entries bij adoptie met een voorlopige stempel; `vraag`-entries seeden
  nooit. **Geen van beide betekent stilzwijgend accepteren** — zie de
  onderbouwingsstap in de skill `adoption-registry`: `ja`-rijen
  moeten bij het opstellen van `PRD.md`/`ARCHITECTUUR.md` alsnog objectief
  onderbouwd worden (of omgezet naar `nee`), `vraag`-rijen krijgen een
  beargumenteerd voorstel in plaats van een blanco vraag.
- **Van toepassing als** — één van de predicaten uit `lib/changes.sh`, de
  bibliotheek die `adopt.sh` en `pending-changes.sh` allebei sourcen. Die lijst
  staat daar en niet hier: een derde kopie in proza loopt vroeg of laat uit de
  pas met de code. De conditie wordt elke sessie opnieuw geëvalueerd, zodat een
  wijziging alsnog opduikt zodra hij relevant wordt voor een project.
- **Ja betekent** — wat er concreet gebeurt bij een `ja`.
- **PR** — de linkback (W21, F15): de PR die dit stelt. Dat is de PR die de
  onderliggende capability daadwerkelijk levert, niet per se de PR die deze
  regel voor het laatst heeft aangeraakt. Bij een latere herschrijving,
  hernoeming of splitsing (zoals `technical-debt-en-refactoring` dat in W6
  uiteenviel in `proces-technical-debt-register` en
  `proces-refactoring-triggers`) blijft de linkback naar de PR wijzen die het
  ding zelf bouwde, niet naar de herstructurering van dit bestand — anders
  wijst de helft van de entries in één klap naar dezelfde
  "fijnmaziger maken"-PR, en dat vertelt een project niets over waaróm de vraag
  bestaat. `./check` controleert alleen dat het veld een URL is, niet of hij
  naar de juiste PR wijst — dat blijft mensenwerk bij het schrijven van de
  entry.

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
en niets anders. De reviewreikwijdte in de skill `pre-merge-review` keyt op dat prefix, dus
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
  toestand, met de voorwaarden per doelomgeving uit de skill `deploy-guards`.
  Is dat nog niet zo, maak er dan een work item voor.
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

## ci-schakel-3-hard-slot

- **Vraag:** Faalt de CI van dit project een pull request die naar geen enkel issue verwijst (schakel 3, hard slot)?
- **Standaard:** ja
- **Van toepassing als:** heeft-package-json
- **Ja betekent:** `check-pr-issue-link.sh` is gescaffold (`adopt.sh`, zie
  `templates/check-pr-issue-link.sh`) en de workflow roept het aan op het
  `pull_request`-event, met het PR-nummer als argument — zie
  `templates/ci.yml`. Alleen de triggerende PR wordt beoordeeld, geen audit
  over de geschiedenis (F13 besluit d, W19b). Dit staat los van
  `ci-op-pr-en-main`: dát antwoord gaat over wannéér de workflow draait, dit
  over een extra stap die hij daarnaast uitvoert. `scaffold_if_missing`
  overschrijft een bestaande `ci.yml` nooit, dus een project dat die al had
  vóór W19b krijgt de stap niet vanzelf — deze vraag maakt dat zichtbaar in
  plaats van stil te laten liggen. Sinds issue #85 heeft `templates/ci.yml`
  ook het `permissions: pull-requests: read`-blok dat deze stap nodig heeft —
  zonder dat blokkeert hij elke PR. Een project dat vóór die fix scaffoldde
  mist het blok — controleer of `pull-requests: read` ergens geldt voor de
  `check`-job (job- of workflow-niveau) — en moet het anders handmatig
  toevoegen of opnieuw scaffolden.
- **PR:** https://github.com/TiesL/claude-workflow/pull/75

## ci-detecteert-main-buiten-pr

- **Vraag:** Faalt de CI van dit project een push naar `main` die niet uit een pull request komt?
- **Standaard:** ja
- **Van toepassing als:** heeft-package-json
- **Ja betekent:** `check-main-via-pr.sh` is gescaffold (`adopt.sh`, zie
  `templates/check-main-via-pr.sh`) en de workflow roept het aan op het
  `push`-event naar `main`, met de commit-SHA als argument — zie
  `templates/ci.yml`. Detectie, geen preventie: het commando is dan al
  uitgevoerd, maar het is het enige mechanisme dat werkt zonder GitHub
  Pro/publieke repo (W27, F17). Beoordeelt alleen de binnenkomende push, geen
  audit over de geschiedenis. Kan de herkomst niet worden vastgesteld, dan
  faalt de controle — bewust het omgekeerde van de native git-hooks (W26,
  `adopt.sh` installeert die altijd, zonder eigen adoptievraag), die bij
  twijfel juist doorlaten. `scaffold_if_missing` overschrijft een bestaande
  `ci.yml` nooit, dus een
  project dat die al had vóór W27 krijgt de stap niet vanzelf — deze vraag
  maakt dat zichtbaar. Sinds issue #85 heeft `templates/ci.yml` ook het
  `permissions: pull-requests: read`-blok dat `check-main-via-pr.sh` nodig
  heeft — het ontbreken ervan is precies wat issue #83 blootlegde: die
  controle riep `gh api .../commits/$sha/pulls` aan en faalde onder het
  default, minimale tokenscope (dat al wél `contents: read` bevat). Een
  project dat vóór die fix scaffoldde mist het blok — controleer of
  `pull-requests: read` ergens geldt voor de `check`-job (job- of
  workflow-niveau) — en moet het anders handmatig toevoegen of opnieuw
  scaffolden.
- **PR:** https://github.com/TiesL/claude-workflow/pull/76

## traceability-schakel-1

- **Vraag:** Moet dit project offline controleren dat elke functionaliteit in `PRD.md` door minstens één scenario in `TEST-SCENARIOS.md` gedekt wordt?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** het project heeft `check-traceability.sh` (gescaffold door
  `adopt.sh`) en roept dat aan vanuit zijn eigen `check`. Scenario's dragen een
  `**Dekt:**`-veld dat naar de functionaliteit verwijst die ze beschrijven.

  **"Ja" betekent met terugwerkende kracht.** Dat is een bewuste keuze, geen
  bijwerking. Het script handhaaft op bestandsniveau: zolang géén enkel scenario
  een `Dekt:`-veld draagt, waarschuwt hij alleen — maar zodra het eerste veld er
  staat, geldt de eis voor **alle** functionaliteit in de PRD, ook voor items
  die niets met dat werk te maken hebben. Er is dus geen geleidelijke ingroei:
  wie het veld voor het eerst invult zonder de rest mee te nemen, zet de hele
  achterstand van het project in één commit rood.

  Antwoord daarom pas "ja" als de bestaande scenario's hun `Dekt:`-velden
  hebben. Voor een project met een reële achterstand is dat een eigen stuk werk,
  geen bijzaak van de eerstvolgende PR — reken op één regel per scenario plus de
  afweging welk scenario welke functionaliteit werkelijk dekt.

  Twee dingen die daarnaast gelden. Een `PRD.md` zonder ID-koppen is een
  waarschuwing, geen fout: schakel 1 valt daar niet te controleren. En
  **dubbele ID's zijn wél een harde fout**, ook zonder enig `Dekt:`-veld — een
  verwijzing naar een ID dat twee keer voorkomt is niet eenduidig op te lossen.
  Een project met dubbele ID's herstelt die eerst; `tennis-invoicing` is dat
  geval vandaag.

  Het prefix ligt niet vast: `F`/`S` is gebruikelijk, maar een project dat zijn
  scenario's `R`/`A`/`B`/`P` nummert werkt ongewijzigd. Alleen het veld telt —
  een ID in lopende tekst is geen verwijzing.
- **PR:** https://github.com/TiesL/claude-workflow/pull/63

---

### Proces en ontwerpdiepte

## proces-prd

- **Vraag:** Houdt dit project een `PRD.md` bij als normatieve specificatie?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` bestaat en wordt actueel gehouden (as-built of ontwerp) — zie `templates/PRD.md`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## architectuurdocument

- **Vraag:** Moet dit project zijn architectuurbesluiten vastleggen in `ARCHITECTUUR.md`?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** structurele keuzes (platform, lagen, eigenaarschap van gegevens, substantiële dependencies) worden vastgelegd met criteria, afgewogen opties, het besluit, de architectuureisen die eruit volgen, en wanneer de keuze herzien zou moeten worden. `adopt.sh` scaffoldt het sjabloon.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## proces-context-document

- **Vraag:** Houdt dit project een `CONTEXT.md` bij: projectjargon → betekenis?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `CONTEXT.md` bestaat en wordt levend gehouden — bijgewerkt
  zodra een nieuwe term ontstaat of van betekenis verandert, niet in één keer
  proberen compleet te maken. Los van `ARCHITECTUUR.md`, dat over structurele
  besluiten gaat, niet over taal. `adopt.sh` scaffoldt het sjabloon zodra deze
  rij op `ja` staat.
- **PR:** https://github.com/TiesL/claude-workflow/pull/72

## proces-issue-tracking

- **Vraag:** Splitst dit project werk op in GitHub-issues (epics/work items)?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `adopt.sh` ververst `.github/ISSUE_TEMPLATE/`, en werk wordt vanuit de PRD opgesplitst in een `Epic`-issue met `Work item`-issues — zie `templates/ISSUE_TEMPLATE/`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## test-unit

- **Vraag:** Heeft dit project unittests voor de kernlogica?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** de kernlogica (idealiter een domeinlaag zonder externe afhankelijkheden — zie `spec-testability`) heeft unittests, en `check` draait ze.
- **PR:** https://github.com/TiesL/claude-workflow/pull/6

## test-feature-gwt

- **Vraag:** Beschrijft dit project functionaliteit als Given/When/Then-scenario's?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `TEST-SCENARIOS.md` bestaat en dekt elk functionaliteitsitem uit de PRD met minstens één Given/When/Then-scenario voor het verwachte gedrag — zie `templates/TEST-SCENARIOS.md`. De faalscenario's daarnaast vallen onder `spec-failure-modes`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## test-tdd-seams

- **Vraag:** Werkt dit project test-first op vooraf afgesproken seams, met rood-vóór-groen-discipline?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** tests raken alleen het publieke grensvlak aan (nooit interne
  implementatiedetails), staan aantoonbaar rood vóór de implementatie, en
  vermijden de drie met naam benoemde anti-patronen (implementatie-gekoppeld,
  tautologisch, horizontaal slicen) — zie de skill `tdd-seams`. Aanvullend op
  `test-unit`/`test-feature-gwt`, die alleen vragen óf er tests zijn, niet hoe.
- **PR:** https://github.com/TiesL/claude-workflow/pull/72

## test-integratie

- **Vraag:** Heeft dit project geautomatiseerde integratietests (over componentgrenzen heen, tegen een echte of gesimuleerde externe afhankelijkheid)?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** naast unittests bestaan er tests die de samenwerking tussen componenten (of met een extern platform) verifiëren, en `check` draait ze — of een expliciete reden waarom dat voor dit project niet proportioneel is.
- **PR:** https://github.com/TiesL/claude-workflow/pull/6

## kwaliteitsreview-voor-merge

- **Vraag:** Moet elke PR in dit project vóór de merge een kwaliteitsreview krijgen, met de bevindingen in de PR?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** vóór de merge draait een review met verse context en op een ander model dan dat de code schreef. De review checkt altijd complexiteit en dependencies (basishygiëne), plus precies de NFR's waarvoor de bijbehorende `spec-*`-vraag in dit project met "ja" is beantwoord. Bevindingen komen in de PR; elke bevinding wordt opgelost of vastgelegd onder *Technical debt* in de PRD.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## ci-poort-op-merge

- **Vraag:** Blokkeert de merge-guard `gh pr merge` ook als de PR checks heeft die niet zijn geslaagd (naast de bestaande blokkade op een ontbrekende review-marker)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** dezelfde guard die al blokkeert op een ontbrekende `pre-merge-review`-marker (zie `kwaliteitsreview-voor-merge`) blokkeert nu ook als `gh pr checks` een check teruggeeft die niet `pass`/`skipping` is — gevonden nadat CI zes runs op rij rood bleek, onopgemerkt (issue #81). Faalt open zonder `gh`, netwerk, of gerapporteerde checks: een project zonder CI (`ci-conventie` is niet van toepassing, of nog niet beantwoord) meldt geen checks en wordt dus niet geblokkeerd. Dezelfde `nee` op `kwaliteitsreview-voor-merge` schakelt beide controles uit — dit is geen los op-of-af, want het is dezelfde poort.
- **PR:** https://github.com/TiesL/claude-workflow/pull/82

## proces-technical-debt-register

- **Vraag:** Houdt dit project een apart Technical debt-register bij naast Bekende beperkingen?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` scheidt *Bekende beperkingen* (blijft zo) van *Technical debt* (per regel: waarom nu acceptabel, en de trigger om het aan te pakken) — beide subsecties staan al in het sjabloon.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## proces-refactoring-triggers

- **Vraag:** Gelden de refactoring-triggers uit de skill `refactoring-triggers` voor dit project?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** een work item dat het vastgelegde ontwerp zou schenden, wordt niet via een omweg toch gebouwd — dat is het signaal voor een eigen herontwerp-work-item. Zie de skill `refactoring-triggers`. De eerste trigger veronderstelt een vastgelegd ontwerp; heeft dit project geen `ARCHITECTUUR.md` (zie `architectuurdocument`), dan gelden alleen de tweede en derde trigger.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## proces-diagnose-bug

- **Vraag:** Volgt dit project bij het diagnosticeren van een bug de dwingende volgorde reproductie → hypotheses → regressietest → fix?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** eerst een deterministische, zelf uitvoerbare reproductie;
  dan falsifieerbare hypotheses, getoond vóórdat ze getest worden; dan een
  regressietest die rood staat op de reproductie; pas dan de fix — zie de
  skill `diagnose-bug`. Een fix zonder voorafgaande falende test bewijst
  niets.
- **PR:** https://github.com/TiesL/claude-workflow/pull/72

---

### Niet-functionele kenmerken (NFR's)

De vijftien niet-functionele kenmerken staan niet hier maar in `nfr/` — één
bestand per kenmerk, met de vraag, wat "ja" betekent en de invulhulp bij elkaar.
Ze stonden eerder zowel hier als in `templates/PRD.md` en moesten met de hand
synchroon blijven; nu zijn beide consument van datzelfde register.

De scripts lezen `CHANGES.md` én `nfr/`, dus voor een project verandert er
niets: dezelfde vragen, op dezelfde momenten. Retirement gaat daar via het veld
`status: geretireerd` in plaats van een verhuizing naar het archief.
