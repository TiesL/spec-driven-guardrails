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

Is Deployability relevant enough for this project to specify (environments,
rollout, rollback)?

## Yes means

`PRD.md` answers the "Deployability" subsection — what environments exist
(e.g. pre-production/production), how rollout works, how you roll back. Its
process-side counterpart is `ci-conventie` and `deploy-guards`.

## Invulhulp

What environments are there (e.g. pre-production/production)? How is it
rolled out? How do you roll back? See also `ci-conventie`/`deploy-guards` in
`CHANGES.md` for the process side of this.
