# Adopteerbare wijzigingen

Elke PR op dit repo die iets toevoegt waarover een project een eigen keuze moet
maken, voegt hier één entry toe. Zonder entry stelt de voorziening in de
projecten geen vraag en denk je ten onrechte dat je gedekt bent — zie
"Adoptieregistratie" in `WORKFLOW.md`.

Per entry:

- **Vraag** — gesloten, met ja/nee te beantwoorden. Houd hem op één regel:
  `pending-changes.sh` toont alleen die eerste regel.
- **Van toepassing als** — één van de predicaten die `pending-changes.sh` kent:
  `altijd`, `heeft-package-json`, `heeft-deploy-script`. De conditie wordt elke
  sessie opnieuw geëvalueerd, zodat een wijziging alsnog opduikt zodra hij
  relevant wordt voor een project.
- **Ja betekent** — wat er concreet gebeurt bij een `ja`.

Het ID is de kop (`##`). Verander een bestaand ID nooit: projecten verwijzen
ernaar in hun `WORKFLOW-ADOPTIE.md`, en een hernoeming laat de vraag daar
opnieuw opduiken.

---

## prd-testscenarios-issue-templates

- **Vraag:** Moet dit project `PRD.md`, `TEST-SCENARIOS.md` en de GitHub-issue-templates gebruiken?
- **Van toepassing als:** altijd
- **Ja betekent:** `adopt.sh` opnieuw draaien — die scaffoldt `PRD.md` en
  `TEST-SCENARIOS.md` als ze ontbreken en ververst `.github/ISSUE_TEMPLATE/`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## ci-conventie

- **Vraag:** Moet dit project de CI-conventie volgen (CI roept alleen `check` aan, geen losse checks in de workflow-YAML)?
- **Van toepassing als:** heeft-package-json
- **Ja betekent:** het project heeft een `check`-script dat typecheck, lint,
  tests en build omvat, en een CI-workflow die uitsluitend dát script aanroept.
  `adopt.sh` scaffoldt `templates/ci.yml` als er nog geen workflow is; een eigen,
  uitgebreidere workflow mag, zolang die de conventie volgt.
- **PR:** https://github.com/TiesL/claude-workflow/pull/2

## deploy-guards

- **Vraag:** Moet dit project de deploy-guards toepassen?
- **Van toepassing als:** heeft-deploy-script
- **Ja betekent:** het deployscript weigert te draaien vanuit een ongeverifieerde
  toestand, met de voorwaarden per doelomgeving uit "Testen en deployen
  automatiseren" in `WORKFLOW.md`. Is dat nog niet zo, maak er dan een work item
  voor.
- **PR:** https://github.com/TiesL/claude-workflow/pull/3

## kwaliteitsreview-voor-merge

- **Vraag:** Moet elke PR in dit project vóór de merge een kwaliteitsreview krijgen, met de bevindingen in de PR?
- **Van toepassing als:** altijd
- **Ja betekent:** vóór de merge draait een review met verse context en op een ander model dan dat de code schreef, tegen de aspecten uit "Kwaliteitsreview vóór de merge" in `WORKFLOW.md`. Bevindingen komen in de PR; elke bevinding wordt opgelost of vastgelegd onder *Technical debt* in de PRD.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## kwaliteitsvragen-in-spec

- **Vraag:** Moet de specificatie van dit project de vijf kwaliteitsvragen en failure-scenario's bevatten?
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` beantwoordt de vijf niet-functionele vragen (toegang, dataconsistentie, failure modes, Observability, grenzen en schaal) — "n.v.t. omdat …" is een geldig antwoord. En elk functionaliteitsitem krijgt in `TEST-SCENARIOS.md` minstens één scenario voor wat er misgaat, naast het verwachte gedrag.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## architectuurdocument

- **Vraag:** Moet dit project zijn architectuurbesluiten vastleggen in `ARCHITECTUUR.md`?
- **Van toepassing als:** altijd
- **Ja betekent:** structurele keuzes (platform, lagen, eigenaarschap van gegevens, substantiële dependencies) worden vastgelegd met criteria, afgewogen opties, het besluit, de architectuureisen die eruit volgen, en wanneer de keuze herzien zou moeten worden. `adopt.sh` scaffoldt het sjabloon.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## technical-debt-en-refactoring

- **Vraag:** Houdt dit project een technical-debt-register bij en volgt het de refactoring-triggers?
- **Van toepassing als:** altijd
- **Ja betekent:** `PRD.md` scheidt *Bekende beperkingen* (blijft zo) van *Technical debt* (per regel: waarom nu acceptabel, en de trigger om het aan te pakken). Refactoring volgt de drie triggers uit "Complexiteit, technical debt en refactoring" in `WORKFLOW.md`, waarvan de belangrijkste is dat een work item het vastgelegde ontwerp niet stilzwijgend mag schenden.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5
