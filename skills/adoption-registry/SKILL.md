---
name: adoption-registry
description: >
  Adoption registry and the substantiation requirement: how a project
  records per change in WORKFLOW-ADOPTION.md what it applies, and how to
  handle a pending or still-to-be-substantiated row (spec-touching vs.
  purely procedural). Use this when a session reports pending workflow
  changes, or when drafting/revising PRD.md or ARCHITECTURE.md.
---

## Why: a choice per change, per project

Not every agreement from `spec-driven-guardrails` fits every project. That's
why every adopted project records in `WORKFLOW-ADOPTION.md` which changes it
applies — so deviating is a registered, substantiated exception instead of
silent drift.

## How a change comes into being

Every PR on `spec-driven-guardrails` that adds something a project must make
its own choice about **adds an entry to `CHANGES.md`** — with a closed
question, a `Standaard` (`ja`/`vraag`), a "Van toepassing als" condition, and what
`ja` concretely means. No entry means no question, and thus a false sense of
coverage; watch for this during review.

`Standaard: ja` vs. `Standaard: vraag` only determines the starting point,
not whether substantiation is needed. When a new project is adopted,
`adopt.sh` sets every currently applicable `Standaard: ja` change to
"`yes` — requires substantiation" (a provisional stamp, not a decision);
`Standaard: vraag` changes are never answered automatically. A missing row
means "not (yet) applicable": if the condition later becomes true — for
example, a project gets a deploy command — the question appears on its own.
A `no` row is a deliberate, substantiated exception and stays in place
until you remove it manually.

## When the question appears

At session start, a hook reports which changes apply to *this* project and
still have no answer (or still say "requires substantiation").

## How to handle it

How you handle a pending or still-to-be-substantiated row depends on the
kind of entry:

- **The entry touches `PRD.md`/`ARCHITECTURE.md`** (most `spec-*` entries
  and the NFRs): this is the **substantiation requirement**, and applies to
  *every* row that belongs here, not only the NFRs from "Niet-functionele
  kenmerken" — `process-prd` or `architecture-document` itself also
  deserves a real reason, not an automatism.
  - A row that still says **"requires substantiation"**: replace it with an
    objective argument, grounded in *this* project, for why `yes` holds —
    or, if that argument doesn't hold up, change the row to `no` with the
    reason.
  - An unanswered **`Standaard: vraag`** row: no blank question. Make a
    reasoned proposal, grounded in this project's actual content, and put
    it to TiesL for confirmation.
  - An auto-seeded `yes` that never gets substantiated is, in practice, no
    different from the silent drift this whole mechanism was meant to
    prevent.
  - **"Applies, but not yet" is not `yes`.** A row whose precondition
    doesn't currently hold — no architecture decision made yet, no test
    suite written yet — is `no`, not `yes` on the strength of intent. Say
    so explicitly in the explanation ("not yet — X doesn't exist yet") and
    name a concrete trigger to revisit, same shape as `PRD.md`'s Technical
    debt table. Found via #239: an agent facing this choice with only
    yes/no in view reached for `yes`, inflating adopted scope with unfilled
    scaffolding counted as if it were real.
- **Purely procedural, touches no specification** (e.g. `ci-convention`,
  `deploy-guards`): a plain **closed yes/no question** suffices, several at
  once in a single choice prompt; in rounds once there are more than four
  questions.

## Recording

Write every answer as a row in `WORKFLOW-ADOPTION.md`:
`| <change-id> | yes/no | <date> | <explanation> |`. The explanation is the
reasoning for every answer, not only for `no` — that's exactly the point of
the substantiation requirement.

On `yes`, carry out what the entry describes under "Ja betekent". If that's
more than a trivial action (e.g. adjusting project code), turn it into a
GitHub issue instead of doing it right away in the same session.

The answer file gets committed: whether a project applies an agreement is a
property of the project, not of whichever machine you happen to be working
on.

## When a row's meaning is tightened after it was already answered (#254)

A `CHANGES.md` entry's "Yes means" clause sometimes changes in a way that
adds a real new obligation — not just prose polish. `quality-review-before-merge`
is the first real case: #244 added the different-model requirement.
A project that already answered `yes` under the old, looser meaning would
otherwise silently keep that stale answer.

If the change is material (adds/removes/changes an obligation, not just
wording), bump the entry's `**Meaning version:**` field in `CHANGES.md`
(absent means version 1; never bump for cosmetic edits — that's the whole
point of the field being a deliberate, hand-set signal rather than
automatic diffing). `pending-changes.sh` then reports every already-
answered row whose recorded version is behind current as its own
"Answered, but the meaning has changed since" notice, distinct from a
never-answered row.

To re-confirm: keep the answer if it still holds, or change it, then add
`(meaning v<N>)` (matching the entry's current version) to that row so it
isn't reported again until the next real tightening.

## When a row's "Applies if" narrows after it was already answered (#258)

The mirror image of the above: instead of "Yes means" getting stricter, an
entry's `**Applies if:**` predicate itself narrows, so a project that used
to be asked stops being asked — with nothing telling it so. #248 is the
first real case: `ci-convention` and its three siblings narrowed from
`has-package-json` to `has-check-command`, silently dropping a project
with an npm `scripts.check` but no root executable `check` (`tennis-admin`,
`a2t-emails`) out of the asked set.

Same signal, same field, same discipline as above — don't build a second
mechanism for this. Whoever edits an `Applies if` predicate in a way that
could narrow who it applies to bumps `**Meaning version:**` exactly like a
material "Yes means" edit would. `pending-changes.sh` then buckets an
already-answered row with a version bump by whether the predicate still
holds for that project right now: still holds → the existing "meaning has
changed" notice; no longer holds → a separate "this project may no longer
be asked" notice, since there the answer itself isn't necessarily stale —
the precondition that made the question relevant is what changed.

Re-confirming is the same either way: keep or change the answer, then add
`(meaning v<N>)` to the row so it isn't reported again for that version.
