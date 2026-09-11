---
name: Work item
about: Concrete, testable piece of work (part of an epic)
title: ""
labels: ""
---

## Description
<!-- What needs to be built/changed, and why -->

## Acceptance criteria
<!--
  Given/When/Then, same notation as TEST-SCENARIOS.md.

  Number them `AC<n>`, not `S<n>`. The latter is TEST-SCENARIOS.md's own
  numbering, and if an issue names its own criteria that way, every search
  for scenario references also hits the issue itself — then it's no longer
  possible to establish which scenario actually has an issue.

  `S<n>` therefore only belongs here as a reference to a scenario, in the
  **Covers:** field below.
-->

### AC1: <name of the criterion>
- Given ...
- When ...
- Then ...

## Related
<!--
  Blocked by / Blocks make the work readable as a dependency graph instead
  of a flat list. Fill in both sides: if the edge sits in only one place,
  the order doesn't read correctly from the other issue, and that's exactly
  where it gets read.

  Deliberately this flat field, not native sub-issues: `gh issue view`
  already shows blocked-by/blocking, and native relations would bind the
  convention to GitHub Projects.
-->
**Epic:** #
**Covers:** <F1, S2>
**Blocked by:** #
**Blocks:** #
<!--
  **Covers:** names what this work item realizes: functionality from
  PRD.md and scenarios from TEST-SCENARIOS.md, comma-separated, e.g.
  `F3, S7, S8`. One field name for both directions — the token's prefix
  already says which way it points.

  Every token matches `^[A-Z]{1,2}[0-9]+[a-z]?$`. That trailing letter
  isn't sloppiness but existing usage (`S2b`); two leading letters occur
  too (`OP4`). Only this field counts — an ID that appears in running text
  is not a reference.

  The prefix isn't fixed: `F`/`S` is customary, but a project that numbers
  its scenarios `R`/`A`/`B`/`P` works unchanged. The check verifies that
  the token resolves to an existing heading, not which letter comes
  before it.
-->
