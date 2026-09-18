# Architecture decision — Multi-agent development orchestration (WIP)

> **Status: WIP exploration, part of epic [#65](https://github.com/TiesL/spec-driven-guardrails/issues/65).**
> This is *not* this repo's own architecture — that is [`ARCHITECTURE.md`](../../ARCHITECTURE.md),
> which records already-shipped structural decisions for the current release. This document
> is the architecture counterpart to [`PRD-MULTI-AGENT-WIP.md`](PRD-MULTI-AGENT-WIP.md): a
> future direction, not yet translated into work items. Decisions below are settled *within
> this WIP exploration* — they don't become binding until the epic's acceptance criteria
> (PRD-MULTI-AGENT-WIP.md §11) are met.

This document records *why* the multi-agent orchestration model is shaped the way it is.
`PRD-MULTI-AGENT-WIP.md` describes what it must do; this is where the structural choices
underneath that live, which alternatives were weighed, and when a choice should be
revisited.

---

## Multiple decisions in one document

Three related decisions share this document, per `templates/ARCHITECTURE.md`'s own
guidance for related-decision sets: shared context representation, decision/escalation
authority, and the role execution model. Requirements, boundaries, dependencies, and open
questions are shared sections at the end, not repeated per decision.

---

## Decision 1 — Shared context is reconstructed from artifacts, not held as orchestrator state

**Decided on 2026-09-17: the orchestrator holds no separate, opaque context object. Context
for any phase is reconstructed by reading the artifacts that phase's role produces or
consumes.**

The workflow spec this was adapted from (`MULTI-AGENT-WORKFLOW.md`, imported from another
project) originally described "each task/feature maintains a unified context object
accessible to all agents." That collides with `PRD-MULTI-AGENT-WIP.md` §3.2: durable,
reviewable artifacts are the evidence of progress, not orchestrator-held state or chat
memory. An opaque context object is neither.

### Evaluation criteria

| Criterion | Why it counts |
|---|---|
| Traceability | A decision or finding that only exists inside orchestrator state can't be audited later — it isn't versioned, isn't diffable, and disappears if the orchestrator session ends. |
| No hidden state | PRD §3.3: completion is a decision based on evidence, judged by artifacts. If context lived somewhere else, "the artifacts" and "what the orchestrator actually used to decide" could silently diverge. |
| Reuse over building new | This repo already has artifact types that carry every layer the imported spec's context object described (issue, `PRD.md`/`ARCHITECTURE.md`, `TEST-SCENARIOS.md`, PR, CI). Building a parallel state store duplicates what already exists. |

### Options weighed

#### Option 1 — Persistent context object (as imported)
A structured object per task, updated by each agent, read by the next. Simple to pass
between sub-agent calls. Rejected: it becomes a second, competing source of truth
alongside the artifacts themselves, and nothing forces the two to stay consistent.

#### Option 2 — Artifact reconstruction (chosen)
The orchestrator builds "context for phase N" by reading the specific files/objects that
phase depends on — issue body, `PRD.md`/`ARCHITECTURE.md` section, `TEST-SCENARIOS.md`
entries, branch commits, PR description, CI/`pre-merge-review` results. Nothing is stored
that isn't already durable and reviewable elsewhere.

### Comparison and choice

Option 2 wins on traceability and avoiding a second source of truth, at the cost of the
orchestrator doing more reading work per phase (re-parsing artifacts instead of holding a
ready-made object). Accepted: this project's scale (solo maintainer, sequential phases,
one change at a time) makes that cost negligible, and the traceability gain is exactly what
PRD §3.2/§3.3 require.

---

## Decision 2 — Escalation and decision authority: one human, one path

**Decided on 2026-09-17: every escalation, regardless of category, routes role-agent →
orchestrator → Ties. No per-category routing to different human leads. Merge/release stays
human-only, permanently — no future auto-approve exception.**

The imported spec assumed an organization with a Product Lead, Tech Lead, QA Lead, Release
Manager, and CTO/Chief Architect, each owning a different escalation category, plus a
"2.0 roadmap" where Dev/QA/Reviewer agents could eventually auto-approve release under
narrow criteria.

### Evaluation criteria

| Criterion | Why it counts |
|---|---|
| Fits the actual organization | This project has one human decision-maker. A routing table across five lead roles models an organization that doesn't exist here. |
| PRD §3.3 (no self-declared completion) | Auto-approving release from within the pipeline that produced the work is the agent declaring its own compliance — exactly what §3.3 rules out. |
| `WORKFLOW.md` step 4 | Already requires Ties' explicit confirmation before every merge, unconditionally. A 2.0 auto-approve exception would contradict a rule this repo already enforces on itself. |

### Options weighed

#### Option 1 — Per-category human leads (as imported)
Different conflict types route to different named roles. Rejected outright: no such roles
exist in this project; simulating them would just mean Ties answering under five different
labels.

#### Option 2 — Single escalation target, phase-progress autonomy without release autonomy (chosen)
Every escalation reaches Ties directly. Agents keep autonomy to auto-progress their own
output to the *next phase* under guardrails (matches the orchestrator's existing "readiness
assessment" authority) — but never to approve a release. That decision is carved out
permanently, not deferred to a "2.0" roadmap.

#### Option 3 — Defer release-autonomy question to a later iteration (rejected)
Keep the imported spec's 2.0 roadmap language as aspirational, revisit later. Rejected:
leaving it in text as a stated future direction risks it being implemented by a later
session that reads `MULTI-AGENT-WORKFLOW.md` without this decision record. Better to close
it now than leave an attractive-looking TBD sitting in the file.

### Comparison and choice

Option 2 wins: it matches this project's real structure (one human) and its existing
merge-confirmation rule, without giving up the orchestrator's useful phase-to-phase
autonomy. Option 3's risk (an unguarded aspiration being acted on later) is exactly the kind
of silent TBD-closing epic #65 rules out.

---

## Decision 3 — Role execution model: fresh orchestrator-dispatched sub-agent per phase

**Decided on 2026-09-17: one role = one context-loading contract, not a standing agent. The
orchestrator (a persistent session) dispatches a fresh, stateless sub-agent per phase per
role. Roles run strictly sequentially. Identity is recorded via a `role:<name>` GitHub
label; no native GitHub assignee.**

### Evaluation criteria

| Criterion | Why it counts |
|---|---|
| No manual session juggling | Ties shouldn't have to open/close sessions by hand to move between roles — that's operational overhead this design should absorb. |
| Matches existing "fresh context" precedent | `pre-merge-review` already requires a fresh-context review, specifically to avoid a reviewer inheriting the author's blind spots. The same reasoning applies to every role, not just Reviewer. |
| No infrastructure this project doesn't have | Parallel/concurrent agent execution and per-role git worktrees are real options elsewhere, but this project has no concurrency need (solo maintainer, one branch active at a time). |
| Avoids redundant assignment mechanisms | The orchestrator already tracks who's working what; a native GitHub assignee would be a second, potentially inconsistent record of the same fact. |

### Options weighed

#### Option 1 — Manual session management
Ties opens and closes a session per role transition by hand. Rejected: pure overhead: the
orchestrator's whole point is to remove exactly this kind of manual coordination.

#### Option 2 — Persistent per-role agent (long-lived)
One agent instance per role, kept alive across the whole project. Rejected: contradicts the
"fresh context per phase" precedent already established by `pre-merge-review`, and
accumulates state that isn't in an artifact — the same problem Decision 1 rules out for the
orchestrator itself.

#### Option 3 — Orchestrator-dispatched fresh sub-agent per phase (chosen)
Orchestrator session stays open; each role's work happens in a one-shot sub-agent call,
scoped to that phase, torn down afterward. Handoff to the next phase happens only through
the artifact the sub-agent produced.

#### Option 4 — Git worktree per role
Isolate each role's file access via a separate worktree/branch checkout. Rejected for now:
solves a concurrency problem this project doesn't have (sequential roles, one branch
checked out at a time); adds a mechanism (worktree lifecycle) with no matching need.

#### Native GitHub assignee vs. label-only identity
Considered making the active role a real GitHub assignee (via a bot account or GitHub App
per role). Rejected for now: the orchestrator is already the source of truth for who's
working what; a native assignee would be a second, potentially stale record of the same
fact, for no operational gain until GitHub's own UI/filtering is actually needed without
going through the orchestrator.

### Comparison and choice

Option 3 wins: no manual session overhead, consistent with the fresh-context precedent
already in this repo, no unneeded infrastructure. What's given up: no parallel role
execution (accepted — matches this project's actual usage) and no OS-level isolation
guarantee between roles (accepted — skill-based file-scope contracts are enough at
sequential, single-branch scale; revisit trigger below).

---

## Architecture requirements that follow from this

### A1 — No orchestrator-held state outside artifacts
The orchestrator never treats an in-memory value as authoritative. If a decision or finding
isn't written to an issue, `PRD.md`/`ARCHITECTURE.md`, `TEST-SCENARIOS.md`, a commit, or a
PR, it hasn't happened yet. Violated the moment the orchestrator "remembers" something a
sub-agent didn't also write down.

### A2 — Merge/release requires Ties' explicit confirmation, unconditionally
No code path, orchestrator rule, or agent recommendation may execute a merge or release
without that confirmation, regardless of how many quality gates already passed. Violated by
any future "auto-merge on green CI + review" shortcut, however well-gated.

### A3 — CI, `pre-merge-review`, and `deploy-guards` are never skippable
On any path — standard, loop-back, or exception (security hotfix, refactor-only, spike,
compliance) — these three gates always run. Only Product/Architect phases may be
abbreviated or skipped. Violated if an exception-path definition ever lists one of these
three as skippable.

### A4 — Each role session gets only the file/directory scope its phase needs
Enforced via a skill-based contract (not OS sandboxing) that states which paths a role may
read/write before it acts. Violated if a role's session is handed unrestricted repository
access "for convenience."

### A5 — `role:<name>` label tracks the currently active phase
The orchestrator updates this label as work moves between phases; it is the traceability
record of "who acted," not an execution mechanism. Violated if the label is left stale
after a phase transition, or if execution logic depends on reading it back (that would make
it state, contradicting A1).

---

## System boundaries and ownership

- **Orchestrator** (persistent session): owns routing, phase-readiness assessment,
  escalation to Ties, and keeping the `role:<name>` label in sync. Does not own any data
  not already owned by an artifact below.
- **Role sub-agents** (Product, Architect, QA, Fullstack Developer, Reviewer): own producing
  one phase's artifact, within their file-scope contract. Torn down after handoff; own no
  persistent state.
- **Existing skills/hooks/CI** (`write-spec`, `pre-merge-review`, `deploy-guards`,
  `tdd-seams`, `check-traceability.sh`, the `pre-commit` branch-name hook): unchanged,
  reused as-is as the gate implementation for the reference process in
  `MULTI-AGENT-WORKFLOW.md`.
- **GitHub** (issues, labels, PRs, CI): owns the actual artifacts and their history. The
  orchestrator reads and writes to GitHub; it doesn't duplicate GitHub's own state.

---

## Dependencies

None new. Uses only what this project already has: Claude Code sub-agent dispatch, GitHub
(issues/labels/PRs), and existing CI/skill infrastructure.

---

## When we would revisit this choice

- **Parallel role execution becomes needed** (e.g. QA and Fullstack Developer working
  concurrently for throughput) — then Decision 3's "sequential only" and "no worktree"
  choices need re-examination; a worktree-per-role (Option 4, rejected above) becomes the
  live alternative.
- **A second human joins as decision-maker** — Decision 2's single-target escalation path
  would need to become a real routing decision again, not a simplification.
- **GitHub-native visibility is needed without going through the orchestrator** — then
  native assignees (bot account/GitHub App per role), rejected in Decision 3, become worth
  the added setup.
- **The orchestrator's re-reading of artifacts per phase becomes a measurable cost** — at
  this project's scale that's not expected, but a much larger PRD/ARCHITECTURE corpus per
  phase could change that calculus for Decision 1.

---

## Still open after this document

Per `PRD-MULTI-AGENT-WIP.md` §9, the following are **deels besloten** (mechanism/process
decided, catalog-level detail still missing) — not to be treated as fully decided by
omission, but also not fully open:

- OQ4 — decided: a bounded-context change is a normal architecture decision (§ "System
  boundaries and ownership" above), revisit trigger reuses `refactoring-triggers`. Still
  missing: who may *propose* a boundary change, and what happens to work already in flight
  on the old boundary when one lands.
- OQ5 — decided: no separate Security agent by default; risk-based trigger list (auth,
  secrets, deploy/CI config, IaC, sensitive data, untrusted input) embedded in Reviewer's
  role contract. Still missing: an enumerated minimal test catalog per trigger category,
  not just the trigger list itself.
- OQ6 — decided: each role verifies a different question (§4's "Kernverantwoordelijkheden
  per rol"); legitimate conflict escalates, doesn't get suppressed. Still missing: the two
  concrete overlaps this leaves unresolved — QA vs. Fullstack Developer on who authors the
  failing test (this project's own `tdd-seams` red-before-green rule makes that
  load-bearing), and Reviewer vs. `check-traceability.sh` on who verifies traceability.
- OQ9 — decided: reuse `WORKFLOW-ADOPTION.md`'s row-per-decision pattern, scoped per work
  item, posted as one orchestrator issue comment. Still missing: a worked example against a
  real work item, to confirm the pattern actually carries the right evidence links.

OQ7 (UX role) is fully decided, not listed here: the activation rule is "any interaction
surface" (GUI, CLI, API, or an agent/LLM harness) — which this repo's own Claude Code usage
already satisfies, so "this repo has none" no longer applies. Nothing catalog-shaped is
missing for OQ7.
