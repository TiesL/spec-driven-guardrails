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
- **Van toepassing als** — één van de predicaten die `pending-changes.sh`
  kent: `altijd`, `heeft-package-json`, `heeft-deploy-script`,
  `heeft-architectuurdocument-bestand`. De conditie wordt elke sessie
  opnieuw geëvalueerd, zodat een wijziging alsnog opduikt zodra hij relevant
  wordt voor een project.
- **Ja betekent** — wat er concreet gebeurt bij een `ja`.

Het ID is de kop (`##`). Verander een bestaand ID nooit **als het al door
een project beantwoord is** — projecten verwijzen ernaar in hun
`WORKFLOW-ADOPTIE.md`, en een hernoeming laat de vraag daar opnieuw opduiken.
Een entry die nog nergens beantwoord is, mag wél herzien of vervangen worden;
controleer dat met `grep` over alle `WORKFLOW-ADOPTIE.md`'s voordat je dat
doet.

---

## prd-testscenarios-issue-templates

**Legacy — bevroren.** Deze entry bundelde bij het ontstaan van deze
voorziening drie dingen die achteraf apart moeten kunnen (PRD, testscenario's,
issue-templates). Al beantwoord in drie projecten, dus het ID blijft staan
zoals het is — maar nieuwe logica gebruikt de fijnmazigere entries hieronder:
`spec-prd`, `architectuurdocument`, `spec-issue-tracking`, `test-unit`,
`test-feature-gwt`, `test-integratie`.

- **Vraag:** Moet dit project `PRD.md`, `TEST-SCENARIOS.md` en de GitHub-issue-templates gebruiken?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `adopt.sh` opnieuw draaien — die scaffoldt `PRD.md` en
  `TEST-SCENARIOS.md` als ze ontbreken en ververst `.github/ISSUE_TEMPLATE/`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

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

---

## Proces en ontwerpdiepte

## spec-prd

- **Vraag:** Houdt dit project een `PRD.md` bij als normatieve specificatie?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` bestaat en wordt actueel gehouden (as-built of ontwerp) — zie `templates/PRD.md`.

## architectuurdocument

- **Vraag:** Moet dit project zijn architectuurbesluiten vastleggen in `ARCHITECTUUR.md`?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** structurele keuzes (platform, lagen, eigenaarschap van gegevens, substantiële dependencies) worden vastgelegd met criteria, afgewogen opties, het besluit, de architectuureisen die eruit volgen, en wanneer de keuze herzien zou moeten worden. `adopt.sh` scaffoldt het sjabloon.

## spec-issue-tracking

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
- **Ja betekent:** `TEST-SCENARIOS.md` bestaat en dekt elk functionaliteitsitem uit de PRD met minstens één scenario voor het verwachte gedrag én minstens één voor wat er misgaat — zie `templates/TEST-SCENARIOS.md`.

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

## spec-technical-debt-register

- **Vraag:** Houdt dit project een apart Technical debt-register bij naast Bekende beperkingen?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` scheidt *Bekende beperkingen* (blijft zo) van *Technical debt* (per regel: waarom nu acceptabel, en de trigger om het aan te pakken) — beide subsecties staan al in het sjabloon.

## proces-refactoring-triggers

- **Vraag:** Gelden de refactoring-triggers uit `WORKFLOW.md` voor dit project?
- **Standaard:** ja
- **Van toepassing als:** heeft-architectuurdocument-bestand
- **Ja betekent:** een work item dat het vastgelegde ontwerp in `ARCHITECTUUR.md` zou schenden, wordt niet via een omweg toch gebouwd — dat is het signaal voor een eigen herontwerp-work-item. Zie "Complexiteit, technical debt en refactoring" in `WORKFLOW.md`.

---

## Niet-functionele kenmerken (NFR's)

Vijftien dimensies, elk als losse subsectie in `templates/PRD.md` onder
*Niet-functionele kenmerken*. Zie de introzin daar voor de
onderbouwingsplicht — deze entries zijn geen los te vinken checklist, elke
`ja` én elke `vraag` vereist een op het project gegronde redenering.

## spec-security

- **Vraag:** Is Security relevant genoeg voor dit project om te specificeren (toegang, autorisatie, secrets)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Security" — wie mag wat, welke rechten zijn minimaal nodig, waar staan secrets.

## spec-data-integriteit

- **Vraag:** Is Data-integriteit relevant genoeg voor dit project om te specificeren (invarianten, idempotentie, gelijktijdig schrijven, correctheid over tijd)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Data-integriteit".

## spec-failure-modes

- **Vraag:** Is Resilience relevant genoeg voor dit project om te specificeren (failure modes en herstelgedrag)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Failure modes", en `TEST-SCENARIOS.md` krijgt per functionaliteitsitem minstens één scenario voor wat er misgaat.

## spec-observability

- **Vraag:** Is Observability relevant genoeg voor dit project om te specificeren?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Observability" — vooral van belang bij achtergrondjobs en triggers die stil kunnen falen.

## spec-performance-schaal

- **Vraag:** Zijn Performance en schaal relevant genoeg voor dit project om te specificeren?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Performance en schaal" — verwachte omvang, platformlimieten, quota.

## spec-deployability

- **Vraag:** Is Deployability relevant genoeg voor dit project om te specificeren (omgevingen, rollout, terugdraaien)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Deployability" — welke omgevingen er zijn (bijv. pre-productie/productie), hoe wordt uitgerold, hoe rol je terug. Het procesmatige tegenhanger hiervan zijn `ci-conventie` en `deploy-guards`.

## spec-privacy

- **Vraag:** Is Privacy relevant genoeg voor dit project om te specificeren (persoonsgegevens, bewaartermijn, inzage)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Privacy" — welke persoonsgegevens worden verwerkt, hoe lang bewaard, wie kan ze zien.

## spec-compliance

- **Vraag:** Is Compliance/auditeerbaarheid relevant genoeg voor dit project om te specificeren (bewaarplicht, controleerbaarheid)?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Compliance en auditeerbaarheid" — welke wettelijke of zelfopgelegde verplichtingen gelden, en hoe je achteraf kunt aantonen dat eraan voldaan is.

## spec-backup-herstel

- **Vraag:** Is Backup en herstel relevant genoeg voor dit project om te specificeren (inclusief disaster recovery)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Backup en herstel" — wat er gebeurt bij dataverlies én bij het wegvallen van de hele omgeving.

## spec-portability

- **Vraag:** Is Portability/vendor lock-in relevant genoeg voor dit project om te specificeren?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Portability" — wat er gebeurt als het gekozen platform verandert of stopt.

## spec-maintainability

- **Vraag:** Is Maintainability relevant genoeg voor dit project om expliciet te specificeren?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Maintainability" — module-indeling, wie moet dit later kunnen begrijpen en wijzigen.

## spec-testability

- **Vraag:** Is Testability relevant genoeg voor dit project om te specificeren?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Testability" — hoe is de code zo gebouwd dat hij te testen is (bijv. een domeinlaag zonder externe afhankelijkheden).

## spec-usability

- **Vraag:** Is Usability/toegankelijkheid relevant genoeg voor dit project om te specificeren?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Usability" — voor wie is dit bruikbaar, en onder welke omstandigheden (bijv. mobiel, direct na de les).

## spec-kostenbeheersing

- **Vraag:** Is Kostenbeheersing relevant genoeg voor dit project om te specificeren?
- **Standaard:** vraag
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Kostenbeheersing" — welke quota of kosten in zicht komen, en wat er gebeurt als je eroverheen gaat.

## spec-documentatie

- **Vraag:** Is Documentatie relevant genoeg voor dit project om expliciet te specificeren (levend houden, evt. API-specificatie)?
- **Standaard:** ja
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de subsectie "Documentatie" — hoe blijven `PRD.md`/`ARCHITECTUUR.md` actueel bij implementatiewijzigingen, en of een formele API-specificatie nodig is.
