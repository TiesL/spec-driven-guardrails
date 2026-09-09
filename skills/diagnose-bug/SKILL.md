---
name: diagnose-bug
description: >
  Reproduction → hypotheses → regression test, in that mandatory order,
  before any fix is even started. Use this when diagnosing a bug, before
  opening a `fix/<name>` branch.
---

## The mandatory order

**1. Reproduction.** First build a deterministic, self-executable
reproduction — a command or test that reliably shows the bug, with no
human step in between. Without that, you won't know at the end whether
you fixed the bug or just stopped seeing it.

**2. Hypotheses — shown before they're tested.** Formulate falsifiable
hypotheses about the cause, and show them to Ties before testing them. Don't
summarize afterward what you tried: hypotheses that are only shared after
the fact can no longer be corrected by someone who doesn't read the code
themselves. A hypothesis you can't refute yourself with a concrete
experiment isn't a hypothesis but a guess.

**3. Regression test — before the fix.** Write the test that captures the
bug before you write the fix, and confirm it's red against the
reproduction from step 1. A fix without a prior failing test proves
nothing: it might work by accident, or address a symptom without touching
the cause.

**4. Fix.** Now apply the actual change, and confirm the regression test
from step 3 turns green.

## Why this order, not another

Each step is a check on the previous one. Reproduction without hypotheses
leads to guess-and-check. Hypotheses without showing them first aren't
correctable. A fix without a prior regression test leaves no proof the bug
was ever gone — only that the code now looks different.

## Relationship to `tdd-seams`

Step 3 follows the same red-before-green discipline as `tdd-seams`,
applied to one specific scenario: the regression test *is* the seam where
this bug occurred, not an internal implementation step.
