---
name: write-spec
description: >
  How work gets specified: keeping PRD.md and TEST-SCENARIOS.md up to
  date, splitting work into GitHub issues, and the Covers:-convention
  (token grammar, traceability) that links scenarios to functionality.
  Use this when drafting issues, PRD sections, or test scenarios.
---

## Specifying work (PRD, test scenarios, issues)

1. Every project keeps a `PRD.md` (as-built or design) and
   `TEST-SCENARIOS.md` (Given/When/Then) — see `templates/` in this repo
   for the format. When a new project is adopted, `adopt.sh` scaffolds
   both automatically if they don't exist yet.
2. Work is split from the PRD into GitHub issues: one `Epic` issue for the
   whole, `Work item` issues per part to be built (see
   `templates/ISSUE_TEMPLATE/`).
3. Every work-item issue has its own Given/When/Then acceptance criteria
   and refers to the matching scenarios in `TEST-SCENARIOS.md` — so every
   issue is directly usable to test the built software against.
4. `PRD.md`/`TEST-SCENARIOS.md` are living documents: update them as soon
   as the implementation diverges from them (as already happens in
   tennis-registration and tennis-invoicing).

For the substantiation requirement when drafting or revising
`PRD.md`/`ARCHITECTURE.md` — see the `adoption-registry` skill.

Does this project have a `CONTEXT.md` (project jargon → meaning, separate
from the structural decisions in `ARCHITECTURE.md`)? Update it as soon as a
new term arises or an existing one changes meaning — don't try to make it
complete in one pass.

## Recording coverage with `Covers:`

Every test scenario carries a `**Covers:**` field under its heading, with
the functionality from `PRD.md` it describes. Comma-separated when there's
more than one. The token form is a fixed grammar: `^[A-Z]{1,2}[0-9]+[a-z]?$`
— for example `F1`, `S2`, or `S2b`. Two leading letters is also allowed
(`OP4`), and that trailing letter (`S2b`) is existing usage, not sloppiness.

Two rules you shouldn't work around. **The prefix isn't fixed**: `F`/`S` is
customary, but a project that numbers its scenarios `R`/`A`/`B`/`P` works
unchanged — the check verifies that a token resolves to an existing
heading, not which letter comes before it. And **only the field counts**:
an ID that appears in running text isn't a reference, otherwise any
sentence that happens to mention "S1" would produce coverage that isn't
really there.

`check-traceability.sh` checks this offline, invoked from the project's
`check`. It isn't retroactive: as long as no scenario carries the field, it
only warns. But note what that means — once the first field appears, the
requirement applies to **all** functionality in the PRD, even items
unrelated to that piece of work. If you fill in the field for the first
time in a project with an existing backlog, do so in a PR that also
addresses that backlog or deliberately records it as debt.
