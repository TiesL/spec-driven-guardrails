---
id: spec-observability
heading: Observability
order: 4
default: yes
applies-if: always
production-gate: no
status: active
---

## Question

Is Observability relevant enough for this project to specify?

## Yes means

`PRD.md` answers the "Observability" subsection — especially relevant for
background jobs and triggers that can fail silently.

## Guidance

How do you notice it's broken? Explicitly for background jobs and triggers:
a job that fails silently fails invisibly.
