# Adoptie van gedeelde workflow-wijzigingen

Per wijziging uit [`CHANGES.md`](https://github.com/TiesL/claude-workflow/blob/main/CHANGES.md)
in `claude-workflow` of dit project hem toepast. Geen rij betekent: (nog) niet
van toepassing — de vraag verschijnt vanzelf zodra dat verandert.

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| prd-testscenarios-issue-templates | nee | 2026-08-13 | `PRD.md` en `TEST-SCENARIOS.md` bestaan hier al; issue-templates voegen niets toe omdat dit project door tennis-admin wordt vervangen en tot de cutover alleen onderhoud krijgt |

`ci-conventie` en `deploy-guards` staan hier bewust niet: dit is een kaal Google
Apps Script-project zonder `package.json` en zonder deploycommando (deployen
gebeurt met de hand in de Apps Script-editor). Krijgt dit project alsnog zo'n
opzet, dan verschijnen die vragen vanzelf.
