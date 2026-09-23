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

## Decision 4 — A two-role conflict escalates as both sides verbatim, not a merged summary

**Decided on 2026-09-21: when the impediment is a genuine disagreement between two roles'
own assessments (not a routine handoff), the orchestrator presents both roles' findings
side by side, verbatim from their own artifacts, to Ties. Never an orchestrator-authored
synthesis, and never only the later role's recommendation.**

### Evaluation criteria

| Criterion | Why it counts |
|---|---|
| Decision 1 (artifact-based context, no hidden state) | An orchestrator-authored summary of a disagreement is itself an unwritten interpretation layer — exactly the "shared context object" Decision 1 already rejected, just applied to escalation instead of routing. |
| Legitimate conflict escalates, doesn't get suppressed (PRD §4, "Kernverantwoordelijkheden per rol") | A merged summary or last-role-only view lets the orchestrator's phrasing quietly resolve the disagreement before Ties ever sees it — the opposite of "escalates." |
| Decision authority stays with Ties, not the orchestrator (Decision 2) | Ties judging from a synthesis means judging the orchestrator's read of the conflict, not the conflict itself. |

### Options weighed

#### Option 1 — Orchestrator-authored merged summary (rejected)
The orchestrator reads both roles' findings and writes one combined account for Ties.
Rejected: this is the orchestrator making an implicit judgment call about which parts of
each side matter — an interpretation step with no artifact of its own, violating Decision
1's own reasoning.

#### Option 2 — Only the later role's recommendation (rejected)
Whichever role escalates last is presented as the current state; the earlier role's
position is assumed superseded. Rejected: a legitimate disagreement isn't automatically
resolved by sequence order — QA finding a design flaw doesn't mean QA is right and
Architect's original reasoning stops mattering.

#### Option 3 — Both roles' findings verbatim, side by side (chosen)
The orchestrator quotes each role's own artifact text directly, unedited, next to each
other. No new artifact is created beyond the escalation comment itself, which only
aggregates pointers/quotes — consistent with Decision 1's "reconstructed from artifacts"
principle.

### Comparison and choice

Option 3 wins: it's the only option that doesn't insert an unwritten interpretation step
between the roles' own artifacts and Ties' decision. Cost: a longer escalation comment than
a summary would be — accepted, since brevity isn't the goal here, an undistorted decision
is.

---

## Decision 5 — Pre-decision elaboration runs as a reduced Product+Architect "co-thinking session", not the full five-role pipeline

**Decided on 2026-09-23: elaborating a new product brief (PRD §3.4 Level 1) or a new
release/epic within an existing product (Level 2) engages only the Orchestrator, Product,
and Architect roles, before any decision to build. QA, Fullstack Developer, and Reviewer do
not participate. Output goes to a dedicated `wip/<slug>/` folder, never directly into
`PRD.md`/`ARCHITECTURE.md`.**

### Evaluation criteria

| Criterion | Why it counts |
|---|---|
| A3 / issue #281 (no phase-skipping in v1) must not be silently reinterpreted | A3 governs Level 3 execution — an already-scoped work item being implemented. Applying it to pre-decision elaboration, where no work item exists yet, would force QA/Fullstack Developer/Reviewer to review nothing — not full engagement, just motion without signal. |
| Main docs stay uncluttered by unaccepted exploration (PRD §3.3, completion is an evidence-based decision) | An idea under active elaboration isn't a decision yet; writing it straight into the accepted docs would blur "proposed" with "decided." |
| Decision 1 (context is artifact-based, reconstructable) | A co-thinking session still needs durable artifacts, not just chat — same principle, smaller role set. |

### Options weighed

#### Option 1 — Run the full five-role pipeline on elaboration work too (rejected)
Forces QA/Fullstack Developer/Reviewer sessions with no implementation yet to inspect —
wasted orchestration for no signal, and it collapses the Level 1-3 granularity distinction
PRD §3.4 already draws.

#### Option 2 — No formal process for elaboration; free-form chat until Ties decides (rejected)
Reintroduces exactly the "decisions lost to chat instead of durable artifacts" problem this
whole epic exists to fix (PRD §2, problem statement) — just relocated to the pre-decision
phase instead of implementation.

#### Option 3 — Reduced pipeline: Orchestrator + Product + Architect only, output to `wip/<slug>/` (chosen)
Matches the granularity PRD §3.4 already assigns to Levels 1-2 (Product alone / Product +
Architect), keeps artifact discipline, and doesn't engage roles that have nothing yet to
evaluate.

### Comparison and choice

Option 3 wins: it's the only option that scales role engagement to what the phase actually
requires without abandoning artifact discipline. Cost: a second, lighter orchestration mode
to maintain alongside the full pipeline — accepted, since Option 1's alternative actively
degrades signal by asking roles to review nothing.

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
any future "auto-merge on green CI + review" shortcut, however well-gated. Deliberately no
escape hatch, unlike A3 below: a human-confirmation gate has nothing to bypass silently —
there is no script to edit around when the constrained party is the one who has to speak.
Ties typing an override *is* the confirmation this invariant describes, not an exception
to it.

### A3 — No phase is skippable or abbreviated in v1, with an explicit, logged escape hatch
All five roles (Product, Architect, QA, Fullstack Developer, Reviewer) fully engage on
every change, on the standard path or a loop-back — there is no exception-path routing
(security hotfix, refactor-only, spike, compliance, or otherwise) in v1 (decided, issue
#281). CI, `pre-merge-review`, and `deploy-guards` were already never-skippable regardless
of path; this extends the same full-engagement principle to every role.

Unlike A2, this one gets a deliberate, loud escape hatch — matching this repo's own
established principle (`deploy-guards`, `hooks/pre-commit`): a guard without an escape
hatch eventually gets bypassed by silently reasoning around it instead of turning it off
explicitly, and A3 is *self-applied by an agent*, not enforced by a script — exactly the
case that principle warns about. It also matches the PRD's own promise (§6) that the
exceptions/override mechanism is explicit, not silently absent.

**The hatch:** a role may be skipped or narrowed only when Ties authorizes that specific
instance. The orchestrator states loudly which role(s) are being skipped and why, and
records it in the work item's compliance comment (the OQ9 evidence pattern already covers
this — no second mechanism). Violated if a role is skipped/narrowed without that
authorization and record, or if any future exception-path definition lists CI,
`pre-merge-review`, or `deploy-guards` as skippable — those three stay absolute, same as
A2, since they're mechanically enforced gates, not a role's own self-applied judgment.

### A4 — Each role session gets only the file/directory scope its phase needs
Enforced via a skill-based contract (not OS sandboxing) that states which paths a role may
read/write before it acts. Violated if a role's session is handed unrestricted repository
access "for convenience."

### A5 — `role:<name>` label tracks the currently active phase
The orchestrator updates this label as work moves between phases; it is the traceability
record of "who acted," not an execution mechanism. Violated if the label is left stale
after a phase transition, or if execution logic depends on reading it back (that would make
it state, contradicting A1).

### A6 — Pre-decision elaboration output lives in `wip/<slug>/`, not in the accepted docs
A co-thinking session (Decision 5) writes its output to its own `wip/<slug>/` folder — a
short, kebab-case, descriptive name, independent of any issue number (unlike branch names,
which this repo's workflow requires to carry one — a co-thinking session may start before
any issue exists). It never edits `PRD.md`/`ARCHITECTURE.md` directly while still unaccepted.
Once Ties accepts the output (same explicit-acceptance gate as PRD §11), its content is
promoted into a new `PRD.md` epic section and a real Epic issue is opened; the `wip/<slug>/`
folder itself is kept afterward by default, as historical record — same precedent as epic
#65's own folder — not deleted, unless Ties says otherwise for that specific case. Violated
if elaboration content is written directly into the accepted docs before acceptance, or if a
`wip/<slug>/` folder is deleted on promotion without Ties saying so.

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

### Proposing a boundary change mid-work (decided 2026-09-21, resolves OQ4's remaining gap)

Any role may notice mid-work that the current bounded-context boundary doesn't fit. This
is **not** a synchronous escalation demanding an immediate decision before work continues
— it's the same "capture as an issue first" discipline this repo already applies to itself
(`WORKFLOW.md`: "no request leads straight to development"). Concretely:

1. The orchestrator files a new GitHub issue capturing the insight (per `write-spec`'s
   conventions), same as any other proposed work.
2. The orchestrator informs Ties that a new issue was filed due to a mid-work insight, and
   asks: pick it up next, leave it open for later, or close it.
3. **Current work continues unaffected on the old boundary regardless of that answer** —
   nothing blocks on Ties' response. The in-flight work item finishes under the boundary it
   started with; a new boundary, once decided, applies to work items opened after that
   decision, not retroactively (same "never rewrite what's already answered" principle as
   `WORKFLOW-ADOPTION.md` rows).

This is a lighter-weight variant of Decision 2's single escalation path, not a new path:
still role-agent → orchestrator → Ties, just as a non-blocking issue + async triage
question instead of an in-line decision gate — because a boundary-change proposal, unlike
a Go/No-Go gate, has nothing that needs deciding before the current work can proceed.

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

None. As of 2026-09-21, all of `PRD-MULTI-AGENT-WIP.md` §9's originally **deels besloten**
questions (OQ4, OQ5, OQ6, OQ9) are fully decided:

- OQ4 — fully decided: a bounded-context change is a normal architecture decision (§
  "System boundaries and ownership" above), revisit trigger reuses `refactoring-triggers`.
  Who may propose a change, and what happens to in-flight work on the old boundary: see
  "Proposing a boundary change mid-work" above.
- OQ5 — fully decided: no separate Security agent by default; risk-based trigger list
  (auth, secrets, deploy/CI config, IaC, sensitive data, untrusted input) embedded in
  Reviewer's role contract, plus a POLP-organized minimal test per trigger category (PRD
  §4, "Security als expliciete verantwoordelijkheid").
- OQ6 — fully decided: each role verifies a different question (§4's "Kernverantwoordelijkheden
  per rol"); legitimate conflict escalates, doesn't get suppressed. Both concrete overlaps
  resolved (PRD §4, "Overlap 1"/"Overlap 2"): QA sets test strategy + scenario, Fullstack
  Developer authors the actual failing test; `check-traceability.sh` verifies structural
  completeness, Reviewer verifies semantic correctness.
- OQ9 — fully decided: reuse `WORKFLOW-ADOPTION.md`'s row-per-decision pattern, scoped per
  work item, posted as one orchestrator issue comment. The worked example against a real,
  already-completed work item (PRD §6, issue #265/PR #279) confirms the pattern actually
  carries the right evidence links.

OQ7 (UX role) is fully decided, not listed here: the activation rule is "any interaction
surface" (GUI, CLI, API, or an agent/LLM harness) — which this repo's own Claude Code usage
already satisfies, so "this repo has none" no longer applies. Nothing catalog-shaped is
missing for OQ7.
