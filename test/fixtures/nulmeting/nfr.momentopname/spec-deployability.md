---
id: spec-deployability
kop: Deployability
volgorde: 6
standaard: ja
van-toepassing-als: altijd
productie-poort: nee
status: actief
---

## Vraag

Is Deployability relevant genoeg voor dit project om te specificeren
(omgevingen, rollout, terugdraaien)?

## Ja betekent

`PRD.md` beantwoordt de subsectie "Deployability" — welke omgevingen er zijn
(bijv. pre-productie/productie), hoe wordt uitgerold, hoe rol je terug. Het
procesmatige tegenhanger hiervan zijn `ci-conventie` en `deploy-guards`.

## Invulhulp

Welke omgevingen zijn er (bijv. pre-productie/productie)? Hoe wordt uitgerold?
Hoe rol je terug? Zie ook `ci-conventie`/`deploy-guards` in `CHANGES.md` voor
de procesmatige kant hiervan.
