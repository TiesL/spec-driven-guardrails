# Adoptie van gedeelde workflow-wijzigingen

Per wijziging uit [`CHANGES.md`](https://github.com/TiesL/claude-workflow/blob/main/CHANGES.md)
in `claude-workflow` of dit project hem toepast. Geen rij betekent: (nog) niet
van toepassing — de vraag verschijnt vanzelf zodra dat verandert.

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| prd-testscenarios-issue-templates | ja | 2026-08-13 | toegepast bij adoptie |
| ci-conventie | ja | 2026-08-13 | eigen `ci.yml` (Node 22, extra buildstap, A1-lintbewaking) die `npm run check` aanroept — volgt de conventie, wijkt bewust af van het sjabloon |
| deploy-guards | ja | 2026-08-13 | nog niet geïmplementeerd: `scripts/deploy.mjs` kent alleen de productie-guards, en nog geen doelomgeving-argument of pre-productiepad |
