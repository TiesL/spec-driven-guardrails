---
id: spec-data-integriteit
kop: Data integrity
volgorde: 2
standaard: ja
van-toepassing-als: altijd
productie-poort: ja
status: actief
---

## Vraag

Is Data integrity relevant enough for this project to specify (invariants,
idempotence, concurrent writes, correctness over time)?

## Yes means

`PRD.md` answers the "Data integrity" subsection.

## Invulhulp

Which invariants must always hold? Which writes must be idempotent (running
twice = the effect of once)? What happens when two things write at the same
time? Does the data stay correct over time — no gradual drift, no silent
corruption?
