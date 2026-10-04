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
floor before this skill existed: "at least as capable as the model that
did Implementation" names no model, only a relation.

**Resolved contradiction (#244), reversed by #392:** `CHANGES.md`'s
`quality-review-before-merge` entry required "a different model than the
one that wrote the code"; this skill's own floor said only "at least as
skilled," permitting the same model. #244 resolved it in favor of the
stricter rule (a genuinely different model whenever more than one capable
model is available, else a recorded `same-model-exception`). #392
reversed that: the floor is the Review stage's model and effort, taken
together, being at least as capable as Implementation's, the cheapest
combination that clears it. A different model is not required, and
`same-model-exception` is retired (legacy: ignored by every script). The
same-model correlated-blind-spot risk "Its limits" warns about is
addressed by choosing a more capable pair, not by a rule about model
identity.

## Per-stage floors

Mapped onto the role table from issue #196 / the multi-agent epic (#65):

| Stage | Role | Floor, stated qualitatively |
|---|---|---|
| Discovery / issue framing | Product | Can turn an ambiguous ask into a well-scoped issue: right acceptance criteria, right edge cases named, right things left out |
| Planning | Architect | Can produce a sound technical approach: right decomposition, right risks surfaced, right sequencing |
| Test/scenario authoring | QA | Can write a test that actually falsifies a wrong implementation — not a tautology, not one that passes by coincidence (see `tdd-seams`) |
| Implementation | Developer | Can satisfy the plan and the test correctly, idiomatically, without over- or under-building |
| Review | Reviewer | At least as capable as what did Implementation, model and effort taken together (same model at higher effort, or a stronger model, whichever clears it more cheaply); a different model is not required, and the reason it clears the floor is recorded as `floor-basis` (#392) |

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

**Machine-readable form (#241).** Produce the marker line with
`.claude/skills/pre-merge-review/model-record-emit.sh --stage <Stage> --model <id>
--effort <e> [--floor-basis '<sentence>']`, run from the project root (the
project's installed skill; the guardrails repo installs its own the same
way), and paste its output unchanged as
the first line of your report; never type a marker by hand (#402: hand-typed
lines with an unquoted value or a quoted stage were unreadable). The
command prints the one valid line, after parsing it back, or nothing and a
reason. This section is the one place the format is written down; the
templates below are what the command prints. Prose alone made this
unenforceable in practice: only the Review stage ever actually got a model
recorded (`portfolio-mgt-agents`, #238). Every stage's record is now also a
marker, in whichever comment (issue, for Discovery; PR, for the rest) that
stage already writes:

```
<!-- model-record: stage=<Discovery|Planning|Test|Implementation|Review> model="<model>" effort="<low|medium|high>" -->
```

Review's marker takes one more field, `floor-basis`: required on every
Review marker, one sentence of free text (#392):

```
<!-- model-record: stage=Review model="<model>" effort="<low|medium|high|unknown>" floor-basis="<one sentence>" -->
```

`floor-basis` is one sentence of free text on why
this model and effort clear Implementation's, for example "same model as
Implementation at higher effort" or "stronger model than Implementation's
at equal effort; the diff is a mechanical rename". A human weighs that
sentence; the gate never verifies it, only that it is present. Any
character is fine in it except a double quote and a control character
such as a newline (see "Marker grammar" below). The
Review report's one-line self-declaration (below) repeats it in prose.
`same-model-exception` is legacy: no script reads it, and it does not
stand in for `floor-basis`.

`effort` is one of `low`, `medium`, `high`, ordered `low < medium < high`.
A role that does not know the effort it ran at records `effort="unknown"`
(not `session-default`): that is honest, and the gate then makes no effort
claim. The `effort` in a marker is self-reported and unverified unless the
platform itself set it; the dispatch tool has no effort argument (A25), so
`unknown` is the honest value for a dispatched role, and a `floor-basis` may
claim "higher effort" only when that effort was actually set.

Record the full model id exactly as the platform reports it (for example
`claude-opus-5`, not `opus`). This is documented, not enforced: a short
alias and the full id of the same model count as different models, since
no script holds a model table, so the effort comparison is skipped for
that pair (recorded as debt in the PRD).

**Marker grammar.** A `model-record` marker is `<!--`, `model-record:`,
`stage=<Stage>` (a bare name, never quoted), then `name="value"`
attributes, then `-->`. A value may contain any character except a double
quote: `>`, `<`, `--` and even `-->` are plain text, so write `floor-basis`
as an ordinary sentence (the command also refuses a newline or another
control character in it). The marker ends at the first `-->` outside
quotes. All three scripts (`model-record-gate.sh`,
`compliance-evidence.sh`, `role-label-staleness.sh`) read markers through
`lib/model-record.sh`, so a `>` in `floor-basis` never hides the marker,
and none counts a marker quoted in a code span, a fence or a blockquote:
that is an example, not a record. A malformed marker (a stray or
unbalanced quote, a quoted stage, no closing `-->`, a `<!--` inside it) is
ignored, never read, and never hides a later marker; the gate names it as
a finding. So does an unquoted, empty or missing `model` or `effort` on the
latest marker of any stage (#402): produce a corrected marker with the
command.

`skills/pre-merge-review/model-record-gate.sh <pr-number>` checks that all
five stages have at least one marker, searched across both the PR's
comments and the comments of every issue it closes — a finding, same
non-blocking shape as every other `pre-merge-review` gate, for any stage
missing one. It also compares Implementation's and Review's latest
markers: the same model with Review's effort lower than Implementation's
is a finding, and so is a Review marker without `floor-basis`.

When the two markers record different models, no script can say which is
more capable: there is no ordering to check, so that comparison is not
machine-checked and rests on the Reviewer's recorded `floor-basis`
judgment. `compliance-evidence.sh` reports that case as
`unverifiable-from-artifacts`.

**Self-declared in the artifact itself, too.** When a stage's own output
is a written artifact a later stage or a human reads directly (a report,
a findings comment, a review) — not only a code change — that artifact
opens with a one-line self-declaration of its own model/effort, in
addition to the marker above. Found missing during epic #65's first
co-thinking-session pilot: the record existed only on the orchestrator's
side, not inside the artifact itself, which is the one place a later role
or Ties actually reads.

## One session or five: depends on `process-multi-agent-roles`

In a project whose `WORKFLOW-ADOPTION.md` answers `process-multi-agent-roles`
yes, each stage runs as its own dispatched role session; see the
`role-contracts` skill and its `ORCHESTRATOR.md`, which the `SessionStart`
hook prints into every session there. One session doing every stage is then
a role-played run: `model-record-gate.sh` flags it and the merge guard
refuses it, unless the human recorded an override. Each role session makes
and records the model choice for its own stage.

Where that row is no or unanswered, a single session moving through
Discovery, Planning, Test authoring, and Implementation in sequence is the
norm, and it still makes (and records) one model-choice decision per stage
it produces an artifact for.

## Who references this skill

`pre-merge-review`'s "Model choice" section is this skill's Review-stage
instance — that skill cross-references here instead of restating the
principle. Any future skill covering Discovery, Planning, or Test
authoring does the same, rather than each inventing its own version.
