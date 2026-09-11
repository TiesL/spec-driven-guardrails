---
id: spec-failure-modes
heading: Failure modes
order: 3
default: yes
applies-if: always
production-gate: no
status: active
---

## Question

Is Resilience relevant enough for this project to specify (failure modes
and recovery behavior)?

## Yes means

`PRD.md` answers the "Failure modes" subsection, and `TEST-SCENARIOS.md`
gets at least one scenario per functionality item for what goes wrong.

## Guidance

What can go wrong — unexpected input, a dependency that drops out, an
expired authorization? What's the behavior then, and how do you recover?
