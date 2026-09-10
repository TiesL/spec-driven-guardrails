# Gearchiveerde wijzigingen

Hier staan entries die niet meer gelden. Ze zijn uit `CHANGES.md` gehaald zodat
elk nieuw project alleen de actuele leeslast draagt, maar ze blijven hier staan
omdat projecten er in hun `WORKFLOW-ADOPTION.md` (of, vóór de laag-B-migratie
W42/#114, hun `WORKFLOW-ADOPTIE.md`) naar verwijzen. Een `grep` over
`CHANGES.md` en dit bestand samen vindt elk ID dat ooit beantwoord is.

**Een entry retireren.** Twee vormen, afhankelijk van wat er al gebeurd is:

- **Nooit ergens beantwoord** — haal hem gewoon weg. Er is geen rij die ernaar
  verwijst, dus er valt niets na te zoeken. Controleer dat met een `grep` over
  alle `WORKFLOW-ADOPTION.md`- én `WORKFLOW-ADOPTIE.md`-bestanden voordat je
  dit doet.
- **Ergens wél beantwoord** — verhuis hem hierheen, met het ID ongewijzigd en
  een expliciete reden. Hernoem `Ja betekent` naar `Ja betekende`.

Laat de velden `Standaard` en `Van toepassing als` in beide gevallen weg: een
entry hier hoort nergens meer geseed of gevraagd te worden. In `CHANGES.md` zelf
is een `## `-kop zonder `Van toepassing als` sinds W6 juist een fout, waar de
gedeelde parser voor waarschuwt — daar is de kop namelijk onvoorwaardelijk een
entry, want sectiescheidingen zijn `###`.

---

## prd-testscenarios-issue-templates

**Reden van retirement:** deze entry bundelde bij het ontstaan van deze
voorziening drie dingen die achteraf apart moeten kunnen (PRD, testscenario's,
issue-templates). Al beantwoord in drie projecten, dus het ID blijft staan
zoals het is. Nieuwe logica gebruikt de fijnmazigere entries die ervoor in de
plaats zijn gekomen, en die in `CHANGES.md` staan: `proces-prd`,
`architectuurdocument`, `proces-issue-tracking`, `test-unit`,
`test-feature-gwt`, `test-integratie`.

- **Vraag:** Moet dit project `PRD.md`, `TEST-SCENARIOS.md` en de GitHub-issue-templates gebruiken?
- **Ja betekende:** `adopt.sh` opnieuw draaien — die scaffoldt `PRD.md` en
  `TEST-SCENARIOS.md` als ze ontbreken en ververst `.github/ISSUE_TEMPLATE/`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1
- **Gearchiveerd:** 2026-09-01, bij W6 (#17) — beantwoord in drie projecten,
  dus bevroren in plaats van verwijderd.
