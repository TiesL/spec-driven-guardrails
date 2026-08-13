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
