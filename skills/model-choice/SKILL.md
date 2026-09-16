---
name: model-choice
description: >
  Capability/cost-aware model selection at every stage of a work item's
  pipeline (Discovery, Planning, Test authoring, Implementation, Review),
  not only review. Floors are described qualitatively, never as a model
  name or tier, so the rule survives new model releases. Use this when
  deciding which model/reasoning effort to use for a stage, or when
  another skill needs to reference the model-choice principle instead of
  restating it.
context: fork
allowed-tools: Read, Grep, Glob
---

## The principle

For every artifact-producing stage of a work item, make an explicit
model-choice decision with two parts:

1. **Floor** — the model (and reasoning effort/thinking budget) must be
   capable enough for what *that specific stage* requires, assessed on
   that stage's own merits — never automatically inherited from whichever
   model handled a previous stage.
2. **Above that floor, optimize for cost** — the least capable (cheapest)
   model/reasoning-effort combination that still clears the floor. A task
   might warrant a strong model at low effort, or a lighter model at high
   effort — both dimensions matter, not just which model family.

No fixed rubric. This is a per-task judgment call, the same as the
existing review-stage rule always was — a simple task gets a light
model, a demanding one doesn't.

## Never name a model or tier

**Floors are stated as what the stage's output has to survive, never as a
model name or tier ("mid-tier", "flagship", a specific model ID).** Tiers
shift as new models are introduced; a name written into this skill today
is stale the moment a new model ships. A qualitative description of the
task's demands doesn't age the same way.

This is the mechanism `pre-merge-review` already used for its reviewer
floor before this skill existed: "at least as skilled as the model that
wrote the reviewed change" names no model, only a relation.

## Per-stage floors

Mapped onto the role table from issue #196 / the multi-agent epic (#65):

| Stage | Role | Floor, stated qualitatively |
|---|---|---|
| Discovery / issue framing | Product | Can turn an ambiguous ask into a well-scoped issue: right acceptance criteria, right edge cases named, right things left out |
| Planning | Architect | Can produce a sound technical approach: right decomposition, right risks surfaced, right sequencing |
| Test/scenario authoring | QA | Can write a test that actually falsifies a wrong implementation — not a tautology, not one that passes by coincidence (see `tdd-seams`) |
| Implementation | Developer | Can satisfy the plan and the test correctly, idiomatically, without over- or under-building |
| Review | Reviewer | At least as capable as the model that did Implementation (existing rule, unchanged) |

Each floor is assessed independently on that stage's own task — a trivial
fix might need little for Planning, but Review's floor still tracks
whatever model did Implementation regardless. The chain isn't
transitive end-to-end; only the Review→Implementation link is fixed
relative to a predecessor.

## The first stage has no predecessor

Every stage after Discovery can anchor its floor to "at least as capable
as the model that did the stage before it" — the Review floor already
works this way. Discovery/Product has no predecessor stage to anchor to:
its floor comes directly from the task's own demands, using exactly its
row in the table above. There is no different mechanism here, just no
predecessor to lean on for this one stage.

## Recording the choice — always, not only when non-obvious

Every stage records which model and reasoning effort handled it, in the
issue, PR, or findings comment — **always**, not only when the choice
deviates from what's obvious. This is stricter than the old
`pre-merge-review` clause it replaces ("if the chosen model deviates from
what's obvious, make that visible"): record every stage's choice, every
time.

The record names the concrete model actually used. That's not in tension
with "never name a model in the floor" above — a floor is an instruction
that has to keep working after new models ship; a record is a fact about
one past invocation, and doesn't need to age well.

## No behavior change to single-agent-per-stage practice

This skill documents the principle ahead of #65's actual multi-agent
orchestration. It doesn't require running each stage as a separate
agent/session today — a single session moving through Discovery, Planning,
Test authoring, and Implementation in sequence still makes (and records)
one model-choice decision per stage it produces an artifact for.

## Who references this skill

`pre-merge-review`'s "Model choice" section is this skill's Review-stage
instance — that skill cross-references here instead of restating the
principle. Any future skill covering Discovery, Planning, or Test
authoring does the same, rather than each inventing its own version.
