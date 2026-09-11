---
name: refactoring-triggers
description: >
  Complexity, technical debt, and refactoring as one loop, and the three
  concrete triggers for paying it down (design contradicted, code touched
  that carries a debt entry, a register that keeps growing). Use this
  when unsure whether something should be refactored now or recorded as
  debt.
---

## Complexity, technical debt, and refactoring

These three aren't separate concerns but one loop: building adds
complexity → whatever of that sticks around becomes technical debt →
refactoring is how you pay it off. Without explicit triggers, that last
step never happens, and code just keeps piling up on top of code.

**Not all complexity is equal.** Essential complexity comes from the
domain itself and can't be refactored away — you manage it with
structure. Accidental complexity comes from how something happens to be
built, and *can* be reduced. Only the second kind can be paid down;
chasing the first is wasted effort.

**Technical debt is broader than complexity alone** — deliberate
shortcuts, outdated dependencies, and missing tests belong to it too. The
register lives in the PRD, with, per row, why it's acceptable for now and
what the trigger is to address it.

**Refactoring is the repayment.** Three triggers, from hard to soft:

1. **The recorded design is contradicted.** If you notice, while doing a
   work item, that it can only be built by violating an architecture
   requirement in `ARCHITECTURE.md`, don't build it anyway via a
   workaround. That's the signal that either the design needs revising, or
   the functionality needs to be designed differently — as its own work
   item, so it happens visibly instead of sinking into the code as an
   unnoticed exception. That's how architectural erosion starts: one
   exception at a time, until no one recognizes the structure anymore.
2. **You touch code that already carries a debt entry.** That's the
   cheapest moment to pay it off — you're already in there.
3. **The register keeps growing while nothing leaves it.** A signal to
   look at what's structurally going wrong, not a hard rule.
