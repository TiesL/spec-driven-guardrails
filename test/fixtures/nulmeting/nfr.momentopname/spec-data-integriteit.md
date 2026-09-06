---
id: spec-data-integriteit
kop: Data-integriteit
volgorde: 2
standaard: ja
van-toepassing-als: altijd
productie-poort: ja
status: actief
---

## Vraag

Is Data-integriteit relevant genoeg voor dit project om te specificeren
(invarianten, idempotentie, gelijktijdig schrijven, correctheid over tijd)?

## Ja betekent

`PRD.md` beantwoordt de subsectie "Data-integriteit".

## Invulhulp

Welke invarianten moeten altijd gelden? Welke schrijfacties moeten idempotent
zijn (twee keer uitvoeren = één keer effect)? Wat gebeurt er als twee dingen
tegelijk schrijven? Blijft de data ook over tijd correct — geen geleidelijke
drift, geen stille corruptie?
