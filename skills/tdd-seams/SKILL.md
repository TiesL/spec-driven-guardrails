---
name: tdd-seams
description: >
  Test-first work on pre-agreed seams: red-before-green discipline and the
  three named anti-patterns to avoid (implementation-coupled,
  tautological, horizontal slicing). Use this when writing tests, or when
  unsure whether a test checks the right thing.
---

## Seams, not internal details

A seam is the public boundary a test may act on — a function signature, a
CLI call, an API response. Never an internal implementation step. Agree on
the seam beforehand, not afterward while writing the test: whoever writes
the implementation first and then picks a seam that happens to fit it is
testing the implementation after the fact, not the behavior.

## Red-before-green

The test comes first, and is demonstrably red before a single line of
implementation is added. That's not an ordering preference but the only
proof that the test actually checks something: a test you've never seen
fail also can't fail when the behavior breaks. This repo applies that to
itself (see "Rood vóór groen" in `TEST-SCENARIOS.md`) — every new scenario
starts red, except the regression scenarios R1–R9, which are supposed to
be green.

## Three anti-patterns, named

**Implementation-coupled.** The test knows internal details (a private
function, an intermediate data structure, the order of internal calls)
instead of only the seam. Such a test breaks on every refactor that leaves
behavior intact — and so rewards code that's never touched again, not code
that's correct.

**Tautological.** The test repeats the implementation instead of checking
the behavior — for example, a mock that returns exactly what the test
expects, or an assertion that performs literally the same calculation as
the code itself. Such a test can't be red by construction, and so proves
nothing.

**Horizontal slicing instead of vertical slices.** Tests per layer (all
repository tests, then all service tests, then all controller tests)
instead of per behavior, seam to seam. Horizontal slicing makes a half-
working scenario look green because each layer was tested separately,
while the layers together don't yet deliver the behavior — vertical, one
scenario at a time, prevents that.

## Relationship to `test-unit`/`test-feature-gwt`

Those two `CHANGES.md` entries only ask *whether* a project has tests.
This skill writes *how* — a separate, additional adoption question
(`test-tdd-seams`), so a project makes its own substantiated choice about
it.
