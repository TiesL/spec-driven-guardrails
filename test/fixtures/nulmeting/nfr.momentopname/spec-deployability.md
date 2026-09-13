---
id: spec-deployability
heading: Deployability
order: 6
default: yes
applies-if: always
production-gate: no
status: active
---

## Question

Is Deployability relevant enough for this project to specify (environments,
rollout, rollback)?

## Yes means

`PRD.md` answers the "Deployability" subsection — what environments exist
(e.g. pre-production/production), how rollout works, how you roll back. Its
process-side counterpart is `ci-convention` and `deploy-guards`.

## Guidance

What environments are there (e.g. pre-production/production)? How is it
rolled out? How do you roll back? See also `ci-convention`/`deploy-guards` in
`CHANGES.md` for the process side of this.
