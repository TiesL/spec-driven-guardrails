---
name: adversarial-review
description: >
  A small number of independent adversarial personas stress-test a draft
  or decision before it's finalized — each a fresh, disposable sub-agent
  dispatch, never one session voicing multiple personas. Usable inside a
  co-thinking session (Orchestrator + Product + Architect, PRD §3.5) or
  standalone before one starts. Not a new standing role.
---

# Adversarial review

From the BMad Method co-thinking session (issue #324, PR #326 — merges into `main`, so its
own `wip/bmad-method-comparison/` reports aren't reachable from this release branch yet;
summarized here rather than cited by path) — Product's candidate 2.5, Architect's correction.
Decided by Ties 2026-09-28: scoped and written now, not invoked as part of closing issue #329
— the first real use is a separate, future event.

## Why this exists

This repo already has one ad hoc precedent: the blameless retrospective used for the
plugin-conversion pilot (`PRD-MULTI-AGENT-WIP.md` §3.5, "Pilot findings incorporated") — one
fresh reviewer per role, plus the orchestrator's own self-assessment, kept as separate,
unmerged artifacts. That pattern worked and produced real process fixes (A7, A8, A9). BMad's
Party mode is a more general, reusable version of the same instinct: a small number of
independent personas reviewing a draft, disagreeing productively, with the human steering.

**BMad's own irony, worth stating plainly (Architect's finding, from the co-thinking
session's direct source-reading of BMad's own docs):** BMad's own Party-mode *default* is
`session` mode — one model voicing every persona — which contradicts BMad's own stated design principle ("one
model voicing five personas tends to make them agree... separate agents keep their reasoning
independent, which is the point"). This repo's existing fresh-subagent-per-role dispatch
(Decision 3 in `ARCHITECTURE-MULTI-AGENT-WIP.md`) is already closer to BMad's *stated*
principle than BMad's own default implementation is. This pattern defaults to independent
dispatch for exactly that reason — never a single session asked to "argue with itself" from
several angles.

## When to use it

Before a Product or Architect draft is finalized — inside a co-thinking session (PRD §3.5) or
standalone, before one even starts — when the orchestrator or Ties judges the draft would
benefit from deliberate, structured pushback rather than a single reviewing pass. Not a
mandatory gate: this is a tool the orchestrator reaches for, not a step every draft must pass
through. Not a new standing role — no persona here has a permanent seat the way Product,
Architect, QA, Fullstack Developer, or Reviewer do.

## How it works

### 1. Persona selection — scoped per invocation, not a fixed roster

Choose 2-4 personas for the specific draft at hand, not a standing cast reused unchanged
every time. Persona framings are questions, not job titles — pick whichever apply to the
draft under review, and add ones not listed here when the draft calls for it:

- **"What's the cheapest way this breaks?"** — the failure-mode adversary: finds the input,
  state, or sequence that defeats the draft's own stated design, not a generic list of
  possible bugs.
- **"What does this contradict that we already decided?"** — the consistency adversary:
  checks the draft against this repo's own already-decided architecture
  (`ARCHITECTURE-MULTI-AGENT-WIP.md`'s A-numbered decisions, `PRD-MULTI-AGENT-WIP.md`), not
  against the adversary's own preferences.
- **"Is this solving a real problem, or one we imagined?"** — the necessity adversary:
  presses on whether the draft's own justification is evidence-backed (a real, observed gap)
  or speculative (a plausible-sounding future need with no current trigger) — same discipline
  `refactoring-triggers`/A3's own escape-hatch reasoning already asks for elsewhere in this
  repo.

This starter set is illustrative, not exhaustive or mandatory. A draft with a different
weak point (e.g. "does this actually reduce ceremony, or just move it") gets a persona framed
for that weak point instead.

### 2. Dispatch — independent, never session mode

Each chosen persona is a separate, fresh sub-agent dispatch (this repo's own `Agent` tool,
same mechanism every role already uses) — never a single session asked to voice multiple
personas in turn. Each persona gets:

- The draft under review, in full.
- Its own framing question (from step 1) as its actual task, not a vague "be adversarial."
- Explicit instruction to find and report real problems, not to manufacture disagreement for
  its own sake — a persona that finds nothing wrong reports that plainly, same as any other
  role's honest "no finding here."
- No visibility into the other personas' output — genuine independence, not sequential
  reaction to what came before.

Findings use this repo's own minimal finding structure (`role-contracts/SKILL.md`, "Shared,
across all five roles": summary, failure scenario, location, category, verdict, severity,
disposition) — no separate format invented for this pattern.

### 3. Reconciliation — back into the source artifact, human steers

The orchestrator collects every persona's findings and folds them back into whatever artifact
triggered the review:

- **Inside a co-thinking session:** appended as a "Deviations/challenges" section in the
  relevant role's report (Product's or Architect's), same as A7's existing convention for one
  role responding to another — quoted, not paraphrased.
- **Standalone, before a co-thinking session starts:** a short standalone note alongside the
  draft, listing each persona's finding and whether the draft's author (if already assigned)
  or the orchestrator judges it resolved, still open, or explicitly overruled with reasoning.

**The human steers, the pattern never decides.** Same principle BMad's own Party mode states
explicitly ("you steer... the party returns the decision to you... not a voting body") and
this repo already holds everywhere else (A2: merge/release is unconditionally human-only;
A10: only a real decision goes to Ties, not a fact a role can look up itself). A persona
disagreeing with the draft's author is a finding for Ties or the orchestrator to weigh, not a
vote that outnumbers the author.

## What this is not

- Not a new standing role — no persona here has a permanent seat among
  `role-contracts/SKILL.md`'s five roles.
- Not a replacement for `pre-merge-review`'s review-depth tiers (candidate 2.4, issue #328) —
  that's a PR-scoped code-review mechanism; this is a pre-decision, draft-scoped pattern for
  co-thinking sessions and elaboration, a different point in the workflow.
- Not mandatory — the orchestrator reaches for this when a draft's own stakes or ambiguity
  warrant it, not as a universal extra gate on every co-thinking session.
