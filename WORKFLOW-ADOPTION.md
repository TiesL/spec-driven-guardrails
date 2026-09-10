# Adoptie van gedeelde workflow-wijzigingen

Per wijziging uit `CHANGES.md` in [spec-driven-guardrails](https://github.com/TiesL/spec-driven-guardrails)
of dit project hem toepast. Geen rij betekent: (nog) niet van toepassing —
de vraag verschijnt vanzelf zodra dat verandert.

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| traceability-schakel-1 | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| proces-prd | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| architectuurdocument | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| test-unit | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| test-feature-gwt | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| test-tdd-seams | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| quality-review-before-merge | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| ci-poort-op-merge | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| proces-technical-debt-register | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| proces-refactoring-triggers | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| proces-diagnose-bug | yes | 2026-09-08 | bij adoptie — requires substantiation tijdens PRD/architectuur |
| spec-security | yes | 2026-09-08 | Relevant, beperkt — de guardrails-hook (F7) is zelf een beveiligingsmaatregel; check-traceability.sh parseert niet-vertrouwde issue-/PR-tekst zonder eval. Zie PRD.md, sectie Security. |
| spec-data-integriteit | yes | 2026-09-08 | Sterk relevant — WORKFLOW-ADOPTION.md is de duurzame vastlegging van besluiten en mag nooit overschreven worden; adopt.sh moet idempotent blijven. Zie PRD.md, sectie Data integrity. |
| spec-failure-modes | yes | 2026-09-08 | Sterk relevant — een hook blokkeert nooit een sessie tenzij dat expliciet zijn taak is (F7/F8), en faalt dan open zonder gh of netwerk. Zie PRD.md, sectie Failure modes. |
| spec-observability | yes | 2026-09-08 | Relevant — stille degradatie (een kapotte symlink achter een hookketen die eindigt op `|| true`) is de belangrijkste faalmodus; check en de verouderde-adoptiemelding zijn het tegengif. Zie PRD.md, sectie Observability. |
| spec-performance-schaal | no | 2026-09-08 | Nauwelijks relevant op deze schaal (O(n·m) over circa 27 entries, verwaarloosbaar) — kort benoemd in PRD.md, sectie Performance and scale, voor de vindbaarheid, geen actieve eis. |
| spec-deployability | yes | 2026-09-08 | Sterk relevant, ongebruikelijke vorm — "uitrollen" is mergen naar main; vier projecten volgen main live via symlink, zonder staging of opt-in. Zie PRD.md, sectie Deployability. |
| spec-privacy | no | 2026-09-08 | Niet van toepassing — geen persoonsgegevens buiten de git-auteursinformatie die er al staat. Zie PRD.md, sectie Privacy. |
| spec-compliance | yes | 2026-09-08 | Niet als wettelijke eis, wel als zelfopgelegde auditeerbaarheid — de adoptieregistratie bestaat juist om aantoonbaar te maken welk project welke afspraak toepast en waarom. Zie PRD.md, sectie Compliance and auditability. |
| spec-backup-herstel | yes | 2026-09-08 | Relevant, laag risico — alles van waarde staat in git; het kwetsbare deel (lokale, ongetrackte symlinks) herstelt via een idempotente adopt.sh-herdraai. Zie PRD.md, sectie Backup and recovery. |
| spec-portability | yes | 2026-09-08 | Relevant, met een bewuste nieuwe binding — skills zijn Claude Code-specifiek (frontmatter als context/model), bash 3.2 is de bredere grens. Zie PRD.md, sectie Portability. |
| spec-maintainability | yes | 2026-09-08 | Sterk relevant, kern van deze release — F3/F4/F5 verwijderen parser-, NFR- en leeslastduplicatie, tegen de kosten van een nieuwe skills-/nfr-/testboom. Zie PRD.md, sectie Maintainability. |
| spec-testability | yes | 2026-09-08 | Sterk relevant, ooit de grootste leemte (nul tests bij veertien gespecificeerde scenario's) — nu een testharnas met 83 scenario's. Zie PRD.md, sectie Testability. |
| spec-usability | yes | 2026-09-08 | Relevant — gebruiker is Ties plus de agent; F6 maakt de onderbouwingslast zichtbaar en faseert haar, in plaats van zeventien rijen huiswerk in één klap. Zie PRD.md, sectie Usability. |
| spec-kostenbeheersing | yes | 2026-09-08 | Relevant, in tokens — WORKFLOW.md laadt volledig in elke sessie van elk project; skillbeschrijvingen kosten weinig, hun body pas bij aanroep. Zie PRD.md, sectie Cost management. |
| spec-documentatie | yes | 2026-09-08 | Relevant — README.md was aantoonbaar verouderd (F16); elke skill draagt zijn eigen uitleg, de kern verwijst er expliciet naar. Zie PRD.md, sectie Documentation. |
