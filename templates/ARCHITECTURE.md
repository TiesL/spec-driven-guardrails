# Architecture decision — <subject of the decision>

This document records *why* the system is the way it is. `PRD.md` describes
what it must do; this is where the structural choices underneath that live,
which alternatives were weighed, and when a choice should be revisited.

Not every decision belongs here. Yes: platform choices, the split into
layers or components, who owns which data, and adding a substantial
dependency. No: how one function is written.

---

## Multiple decisions in one document

The skeleton below is written for the common case: one project, one
architecture decision. A project with several *related* decisions doesn't
need a separate document per decision — see `tennis-invoicing`'s own
`ARCHITECTUUR.md` for a real example: three related decisions (platform
choice, a data-registration pattern, and a dual-entrypoint structure)
share one document without the result becoming hard to follow.

The pattern:

- Repeat the **The decision / Evaluation criteria / Options weighed /
  Comparison and choice** block once per decision, as its own `## Decision
  N — <name>` section (with `### Evaluation criteria`, `### Options
  weighed`, and `### Comparison and choice` nested under it).
- Everything from **Architecture requirements that follow from this**
  onward — requirements, system boundaries, dependencies, revisit
  triggers, open questions — stays a single, shared section for the whole
  document, not repeated per decision. Requirements from different
  decisions can live together in one numbered `A<n>` list.

A project with exactly one decision ignores this section and uses the
skeleton below exactly as it is — nothing about the single-decision path
changes.

---

## The decision

**Decided on <date>: <the choice, in one sentence>.**

<Two to five sentences: what was chosen, and what that means concretely for
what the system looks like.>

---

## Evaluation criteria

<What were the options judged against, and why those criteria? Name them
before the options — otherwise you pick, after the fact, the criteria that
justify the outcome you wanted.>

| Criterion | Why it counts |
|---|---|

---

## Options weighed

### Option 1 — <name>
<What it is, and how it scores on the criteria. Pros and cons.>

### Option 2 — <name>
<Same.>

---

## Comparison and choice

<Why the chosen option wins. Name explicitly what you're giving up for it —
a choice with no downsides is usually a choice that wasn't examined closely
enough.>

---

## Architecture requirements that follow from this

Numbered, testable requirements the code adheres to. These are the yardstick
for the refactoring trigger in `CLAUDE.md`: if you're building something
that violates a requirement here, that's a signal to redesign, not to make
an exception.

### A1 — <name of the requirement>
<What the requirement entails, and why — what problem does it prevent? How
do you tell if it's being violated?>

---

## System boundaries and ownership

<What components are there, and what's the agreement between those
components? Who owns which data? What may and may not look directly into
each other?>

---

## Dependencies

Adding a library is an architecture decision, not an implementation detail.
Per substantial dependency:

| Dependency | For what | Maintenance and maturity | License | Why not build it ourselves |
|---|---|---|---|---|

---

## When we would revisit this choice

<Concrete, recognizable signals — not "if it stops feeling right." For
example: a limit coming into view, an assumption turning out to be false, a
piece of functionality that structurally doesn't fit.>

-

---

## Still open after this document

<What's deliberately not yet decided, and when should it be?>

-
