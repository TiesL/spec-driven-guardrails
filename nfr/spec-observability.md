---
id: spec-observability
kop: Observability
volgorde: 4
standaard: ja
van-toepassing-als: altijd
productie-poort: nee
status: actief
---

## Vraag

Is Observability relevant enough for this project to specify?

## Yes means

`PRD.md` answers the "Observability" subsection — especially relevant for
background jobs and triggers that can fail silently.

## Invulhulp

How do you notice it's broken? Explicitly for background jobs and triggers:
a job that fails silently fails invisibly.
