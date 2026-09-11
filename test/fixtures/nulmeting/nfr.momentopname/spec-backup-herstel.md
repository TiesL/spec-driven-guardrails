---
id: spec-backup-herstel
heading: Backup and recovery
order: 9
default: yes
applies-if: always
production-gate: yes
status: active
---

## Question

Is Backup and recovery relevant enough for this project to specify
(including disaster recovery)?

## Yes means

`PRD.md` answers the "Backup en herstel" subsection — what happens on data
loss, and on the entire environment disappearing.

## Guidance

What happens on data loss within a working environment? What happens if the
environment itself disappears (disaster recovery) — an account, a script
project?
