---
id: spec-failure-modes
kop: Failure modes
volgorde: 3
standaard: ja
van-toepassing-als: altijd
productie-poort: nee
status: actief
---

## Vraag

Is Resilience relevant enough for this project to specify (failure modes
and recovery behavior)?

## Yes means

`PRD.md` answers the "Failure modes" subsection, and `TEST-SCENARIOS.md`
gets at least one scenario per functionality item for what goes wrong.

## Invulhulp

What can go wrong — unexpected input, a dependency that drops out, an
expired authorization? What's the behavior then, and how do you recover?
