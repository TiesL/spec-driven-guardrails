# PRD — Multi-agent software development in the agentic development workflow

| Field | Value |
| --- | --- |
| Status | **Work in progress (WIP) — for exploration and review** |
| Target release | **TBD** — next release of the existing agentic development workflow |
| Work item type | Proposal for a GitHub Epic and follow-up work items |
| Epic | [#65](https://github.com/TiesL/spec-driven-guardrails/issues/65) — Multi-agent software development in the workflow (WIP exploration) |
| Owner | Ties |
| Last updated | September 26, 2026 |

> This document describes a desired direction, not a definitive architecture or implementation plan. Decisions, concrete tooling, and technical elaboration remain explicitly **TBD**.

> **Relationship to the other documents in this repo.** This is *not* the PRD of
> the current release — that is [`PRD.md`](../../PRD.md) ("From prose to mechanism",
> epic [#11](https://github.com/TiesL/spec-driven-guardrails/issues/11)). This document
> is an exploration for a later release and has not yet been translated into
> work items; that only happens after explicit decision-making. The workflow agreements
> referenced below are in [`WORKFLOW.md`](../../WORKFLOW.md).

## 1. Summary

The agentic development workflow is being extended with a model for multi-agent software development. The goal is not just to divide work across agents, but to organize predictable software development in which responsibilities are separated, work demonstrably follows the workflow, and quality does not rest on self-declaration.

Agents work with a bounded context and specialized responsibilities. They collaborate via explicit, reviewable artifacts — for example requirements, specifications, designs, tests, GitHub Issues, documentation, pull requests, and CI results — instead of solely through informal hand-offs. An orchestration mechanism guards the order, dependencies, gates, and the evidence needed to let work proceed or be considered complete.

## 2. Goal and problem statement

### Goal

Extend an existing agentic development workflow so that a team of AI agents can develop software within the same development agreements that apply to the project, with verifiable compliance and clear quality gates.

### Problem statement

Without an explicit collaboration and governance model, multiple agents can:

- interpret the same context differently or contradict each other;
- skip responsibilities or duplicate them;
- treat work as "done" without independent evidence;
- follow the agreed development workflow only partially;
- record knowledge and decisions only in chat hand-offs, leaving traceability absent.

The desired solution is therefore not a collection of individually directed agents, but a development system in which work, decisions, checks, and hand-offs can be found in shared artifacts and demonstrable gates.

### Desired outcome

For a change, it must be visible and verifiable:

```text
Requirement → specification → test(s) → GitHub work item(s) → implementation → pull request → CI/review → integration/deployment
```

The exact artifact types, relations, and automation will be determined in follow-up design.

## 3. Product vision and design principles

### 3.1 Context isolation and specialized responsibilities

Every agent gets a purpose-bounded context: only the information, authority, and artifacts needed for the assigned responsibility. This limits noise, uncontrolled assumptions, and unintended overlap.

Specialization is primarily determined by a coherent responsibility, not by a traditional technical layer. A responsibility can be carried out by one agent, shared across several agents, or organized differently in later iterations.

### 3.2 Collaboration via explicit artifacts

Agents deliver work as durable, reviewable artifacts. A subsequent role bases its work on those artifacts and likewise records its own findings. Examples are:

- requirements and acceptance criteria;
- specifications and architecture or design decisions;
- test cases and test results;
- GitHub Issues and their relations to each other;
- code, repository documentation, and Infrastructure as Code;
- pull requests, review comments, and CI results.

Chat messages can coordinate, but are not the primary evidence of progress, quality, or traceability.

### 3.3 Completion is an evidence-based decision

An agent may carry out work and produce evidence, but does not independently decide that that work meets all requirements. Progress and completion follow from predefined gates, assessed on artifacts and evidence by the roles and/or automation designated for that purpose.

Among other things, this means that an implementation is not "done" merely because code has been written: relevant tests, review, CI results, traceability, and other agreed controls must be demonstrably present.

### 3.4 Work granularity: product brief, release, feature (decided, 2026-09-21)

Three levels, each with its own artifact, increasing in scope:

| Level | Trigger | Artifact | Role |
| --- | --- | --- | --- |
| 1. New product | Project originates | Product brief — becomes `PRD.md` itself | Product (only; Architect not yet involved) |
| 2. New release/initiative within an existing product | Scope large enough for its own Epic | Section in `PRD.md` + Epic issue | Product + Architect |
| 3. Feature within a release | One bounded delivery | Work item issue + scenarios in `TEST-SCENARIOS.md` (`Covers:` token) | Product/Architect (issue) → QA → Fullstack Developer → Reviewer |

A new product goes through all three levels, in that order. Level 3 has no separate brief artifact up front: the issue itself carries the condensed product-brief content (see below).

**Format of that condensed content in an issue:** Jobs-to-be-done or user story, depending on whether `PRD.md` names a concrete end-user persona besides the maintainer/developer themself.

- `PRD.md` names an external end-user persona → **user story** ("As a [user type] I want [goal], so that [reason]").
- `PRD.md`'s target audience is the maintainer, other developers, or the workflow itself (like this repo) → **Jobs-to-be-done** ("when [situation], I want [motivation], so that [outcome]").

This rule is not recorded separately per project (no extra field in `CONTEXT.md`) — the intent is that the `write-spec` skill should check against `PRD.md`'s target audience at every issue write-up, so the rule can't be forgotten and can't go stale. That is not yet implemented: `skills/write-spec/SKILL.md` today contains no JTBD/user-story/target-audience check.

Concrete placement in `templates/ISSUE_TEMPLATE/epic.md`/`work-item.md` (which field this rule replaces or supplements) is **out of scope for this WIP** — see §8. That is a template change like any other and only becomes a decision once those templates are actually changed, not decided ahead of time here.

### 3.5 Pre-decision elaboration: co-thinking sessions (decided, 2026-09-23)

Levels 1 and 2 in §3.4's table (new product; new release/epic within an existing product)
happen *before* a decision to build. This elaboration/elicitation step runs as a
**co-thinking session**: Orchestrator + Product + Architect only — QA, Fullstack Developer,
and Reviewer do not participate, because there is nothing yet to test, implement, or review.
Full detail (evaluation criteria, options weighed, the architecture requirement it produces)
is in [`ARCHITECTURE-MULTI-AGENT-WIP.md`](ARCHITECTURE-MULTI-AGENT-WIP.md), Decision 5 and
A6.

This does not conflict with issue #281's "no phase-skipping in v1" decision (§6,
"Orchestrator: decided model" above; A3 in `ARCHITECTURE-MULTI-AGENT-WIP.md`) — that
decision governs Level 3 execution, where a work item already exists and all five roles
fully engage on it. A co-thinking session is an earlier, separate layer: there is no work
item yet, so there is nothing for QA/Fullstack Developer/Reviewer to engage with.

Output goes to a dedicated `wip/<slug>/` folder (short, kebab-case, descriptive name — not
tied to an issue number, since a co-thinking session may start before any issue exists),
never directly into `PRD.md`/`ARCHITECTURE.md`. Once Ties explicitly accepts the output
(same acceptance gate as §11), it gets promoted into a new `PRD.md` epic section and a real
Epic issue; the `wip/<slug>/` folder itself is kept afterward as historical record by
default, not deleted — same precedent as this very epic's own `wip/multi-agent-development/`
folder.

**Second run (2026-09-26): rolling out this very epic.** The same pattern ran again, this time
against making epic #65's own design executable — output in
[`wip/multi-agent-rollout/`](../multi-agent-rollout/PRODUCT-REPORT.md), promoted to epic #295.

**Pilot findings incorporated (2026-09-25).** The pattern above ran for the first time
against `wip/claude-code-plugin/` (Product then Architect, sequential, each a fresh sub-agent
producing a durable report). A blameless retrospective — one fresh reviewer per role plus the
orchestrator's own self-assessment, kept as three separate, unmerged artifacts
(`CO-THINKING-PILOT-RETRO-PRODUCT.md`, `-ARCHITECT.md`, `-ORCHESTRATOR.md`) — surfaced process
gaps now closed in `ARCHITECTURE-MULTI-AGENT-WIP.md` (A7, A8, A9, and the Decision 4
addendum). Two further rules for whoever runs the orchestrator role, not rising to
architecture invariants but load-bearing for every future co-thinking session:

- **Never ask a second-or-later role in the chain for a "final" decomposition/output while
  also asking it to flag disagreements with the prior role.** Those two asks pull against
  each other — "final" nudges toward treating that role's framing as the resolved account,
  undercutting the disagreement-flagging asked for in the same breath. Ask instead for "a
  proposed [output], with every deviation from the prior role's [output] marked and
  reasoned."
- **Every role's report opens with a one-line model/effort declaration** (e.g. "Model/effort:
  Claude Opus, [role] role") — self-declared in the artifact itself, not only recorded
  orchestrator-side, per the `model-choice` skill's "record every stage, always" principle.

## 4. Roles and responsibilities

The roles below are core roles in the intended model. These are responsibilities; the assignment to concrete agents is **TBD**.

| Role | Primary responsibility | Examples of evidence / gates |
| --- | --- | --- |
| Product | Make the problem, desired outcome, requirements, and acceptance criteria explicit and validate them on substance. | Requirements, acceptance criteria, product validation. |
| Architect | Guard coherence, technical feasibility, boundaries, quality requirements, and design decisions. | Specification/design, architecture review, recorded decisions. |
| QA | Determine test strategy (which kind of test — unit/integration/end-to-end/penetration/etc. — fits this change) and test scenarios/seams; guard quality risks and verification of behavior. | Test strategy, test scenarios/seams, test results, QA assessment. |
| Reviewer / Lead Developer | Independently assess: evidence that the preceding work actually happened; code quality, abstractions, reuse, verbosity/efficiency. | Pull request review, technical findings, approval or rejection. |
| Fullstack Developer | Implement a coherent, bounded part end to end, including relevant tests and documentation. | Implementation, red/green tests, documentation, pull request. |

### Core responsibilities per role (decided)

In addition to the roles table above, per role the core responsibilities and which question that role answers (this is what prevents overlap — every role answers a different question, not the same question again):

- **Product**: determines product vision and releases, prioritizes features/requirements based on business/user need, makes trade-off and scope decisions. Answers: *is the requirement itself correct and complete?*
- **Architect**: designs system structure (application, software, integration, data, and infrastructure architecture), records technology choices and standards, safeguards scalability/performance/maintainability, assesses major technical decisions, mitigates technical risk. Answers: *does the design meet the requirement and the architecture principles?*
- **QA**: determines test strategy (which kind of test fits — unit/integration/end-to-end/penetration/etc.) and works out test scenarios/seams, runs them, identifies/reports defects, verifies functional and non-functional requirements, guards quality gates before release. Answers: *what needs to be tested, in what way, and does the implementation behave according to those tests?*
- **Fullstack Developer**: builds features/fixes to specification, **writes the actual test code per QA's test strategy/scenarios** (red-before-green, see `tdd-seams`), writes maintainable code, manages code quality and technical debt, delivers working software.
- **Reviewer**: independent final gate — verifies there is evidence that the preceding work actually happened and that the collection of artifacts is consistent for release; also assesses code quality, abstractions, reuse, and verbosity/efficiency (the same scope as this repo's own `pre-merge-review`/`code-review`). Remains its own role (not merged with QA/Fullstack Developer) — this repo's own `pre-merge-review` (F11) exists specifically because, across four projects and 27 merged PRs (`PRD.md`), not one of them had review; self-checking by the same role does not solve that problem.

**Additional role responsibilities (decided 2026-09-25, in English — full text in
`role-contracts/SKILL.md`, which this paragraph mirrors so it isn't the sole record):**

- **Product** also writes the business case for a product, release, or feature, and
  prioritizes on business/user value weighed against effort — effort is estimated by
  Architect, QA, Fullstack Developer, and Reviewer, each for their own share of the work,
  never by Product itself. Prioritization framework method is TBD (e.g. an impact/effort
  matrix or WSJF). Product elicits requirements from Ties using the vendored `grilling`
  skill's design-tree/frontier/rounds method (`role-contracts/SKILL.md`, `vendor/grilling/`).
- **Architect** also decomposes the system per the vendored `codebase-design` skill's deep-
  module vocabulary (Module, Interface, Seam, Depth, Leverage, Locality —
  `role-contracts/SKILL.md`, `vendor/codebase-design/`), and estimates implementation effort for
  Product's prioritization.
- **QA** and **Fullstack Developer** and **Reviewer** each also estimate effort for their own
  share of the work, for Product's prioritization.
- **Fullstack Developer** implements within Architect's decomposition (same vendored
  `codebase-design` vocabulary), respecting decided seams/module boundaries; internal seams
  private to its own implementation remain its own call.
- **QA does not execute tests itself** — Fullstack Developer writes and runs them
  (red-before-green), CI re-runs independently; QA verifies results against its own
  scenarios. **Reviewer does not re-run tests either** — checks CI's actual result and judges
  strategy adequacy, and additionally verifies the actual test code faithfully implements
  QA's scenarios (extends Overlap 2's structural/semantic split to test code — see the gap
  closed further below).
- A defect or finding (QA, Reviewer) uses a minimal content structure: summary, failure
  scenario (evidence, not assertion), location (file:line or scenario ID), category, and a
  `CONFIRMED`/`PLAUSIBLE` verdict — full detail in `role-contracts/SKILL.md`.

**Overlap 1 — who writes the failing test (QA vs. Fullstack Developer)?** (decided, resolves §9 OQ6) No overlap once the question is split: QA determines *what* needs to be tested and *which kind of test* fits it (the strategy/the seam) — that is QA's existing "determine test strategy" responsibility, now explicitly including the choice of test kind. Fullstack Developer writes the *actual test code*, red-before-green, as part of implementation — that is exactly what `tdd-seams`' own red-before-green discipline already describes (the seam is agreed in advance, the red test belongs to the implementation step). No new rule, just the existing division of roles made explicit.

**Overlap 2 — who verifies traceability (Reviewer vs. `check-traceability.sh`)?** (decided, resolves §9 OQ6) Also no overlap: `check-traceability.sh` verifies *structurally* (link 1, offline, mechanical) — does *a* scenario exist per functionality, do `Covers:` tokens resolve. That's something the script can establish, it isn't a judgment. Reviewer verifies *semantically* — is it the *right* scenario for the *right* functionality, does it actually cover the behavior the requirement asks for. That is precisely the kind of judgment a mechanical check cannot make. Different question, not duplicate work.

**Gap closed (decided 2026-09-25, in English — see `role-contracts/SKILL.md`): who checks that
Fullstack Developer's actual test code faithfully implements QA's scenarios/strategy, not
just that it exists and passes?** Overlap 1 only resolved *who writes* the test; nothing
resolved who verifies it matches intent. Extends Overlap 2's structural/semantic split to
test code specifically: Reviewer judges this, since it's the same kind of judgment
`check-traceability.sh` can't make, and Reviewer is the only role positioned after Fullstack
Developer in the standard path (there is nowhere else for this check to live).

**Defect/finding content structure (decided 2026-09-25, in English — see
`role-contracts/SKILL.md`'s "Shared, across all five roles" section for the full template).**
Neither QA's "identifying/reporting defects" nor Reviewer's technical findings had a
defined content shape before this — closed rather than left implied. Minimal fields:
summary, failure scenario (evidence, not assertion), location (file:line or scenario ID),
category, and a `CONFIRMED`/`PLAUSIBLE` verdict. No new tooling — the same shape this
project's own review-finding conventions already produce, written down explicitly.

Coherence: Product determines *what*; Architect determines *how*; Fullstack Developer executes; QA verifies that it works as intended; Reviewer independently confirms the whole chain before release.

**Conflict is expected, not a flaw in the model.** A different question per role prevents *redundant* re-verification, not legitimate conflict (e.g. Architect's design vs. Product's requirement, or QA finding a design flaw). Such conflicts escalate via the already-decided single path — role agent → orchestrator → Ties — see the Escalation Triggers in `MULTI-AGENT-WORKFLOW.md` (categories 1 and 2 there). **When escalating a conflict between two roles, the orchestrator presents both roles' own findings side by side** (decided, `ARCHITECTURE-MULTI-AGENT-WIP.md` Decision 4) — no merged summary, no last-role-only account — so Ties himself assesses from both positions, not via orchestrator interpretation.

### Security as an explicit responsibility

Security testing and checking security-relevant risks are an explicit responsibility in the workflow. This does not automatically mean a separate Security agent is needed. Depending on risk, expertise, and automation, the task can be part of several roles or later still be set up as a separate role/agent.

**Minimal gates and risk-driven application (decided):** no separate mechanism — reuses the existing `security-review` skill. Reviewer invokes it (checklist item "Security & Compliance", already present in `MULTI-AGENT-WORKFLOW.md`) when a change touches: auth/session management, secrets/credentials, deploy/CI configuration, Infrastructure as Code, sensitive/personal data, or an interface that receives untrusted input (API/CLI/webhook) — risk-driven, not always-on. No new risk taxonomy: the same OWASP-top-10-like categories this project already implicitly uses as a baseline.

**Embedding of the trigger list:** text in the skill that records Reviewer's role contract (still to be written, see "Role-to-agent assignment" below) — the same place as Reviewer's other checklist items, no new artifact type. Optional addition: a deterministic, path-based CI flag (touches `auth/`, `.github/workflows/`, IaC folders, deploy scripts) in the style of `check-pr-issue-link.sh` — does not replace Reviewer's own assessment, only catches the obvious cases.

**When a separate Security agent is justified:** the same conditional-escalation reasoning as for UX below — when the trigger list applies *and* the stakes are high (real user credentials, payment data, publicly accessible production environment), not by default.

**Minimal test catalog per trigger category (decided, resolves §9 OQ5):** POLP (Principle of Least Privilege) as the organizing premise, for both implementation and test — not six standalone ad-hoc checks, but the same question every time: *is this limited to the minimum actually needed, and does a test prove that exceeding it is refused?*

| Trigger category | Minimal test (POLP question) |
| --- | --- |
| Auth/session management | Access with less than the required role/scope is refused — not just "unauthorized refused" in general, but specifically *excess* privilege refused. |
| Secrets/credentials | The credential used itself has minimal scope (a scoped token, not a master key); no secret value leaks into logs/diff/output (this repo's own `gitleaks` work, #264). |
| Deploy/CI configuration | The granted permissions/scope are the minimum for the task — as this repo's own CI already does (`contents: read` explicit, only expanded when a step genuinely needs it). |
| Infrastructure as Code | The provisioned resource/role has minimal privileges, no broad/wildcard grants; a plan/dry-run diff is reviewed before apply, never applied blindly. |
| Sensitive/personal data | Access to the data is limited to what is actually needed (minimal scope, minimal retention period) — per the privacy NFR. |
| Untrusted input (API/CLI/webhook) | The input handling operates with minimal privileges on that input — validates before use in a privileged operation, never passes untrusted input directly into a privileged operation (this repo's own "no `eval`" principle, applied more broadly). |

This is the missing catalog itself, not a new taxonomy — the trigger list above remains unchanged.

### UX as a conditional responsibility (decided activation rule)

No separate UX role by default. The activation rule is **not** "is there a UI" — that misses, for example, an agent that operates through an LLM harness (such as Claude Code), where that harness itself is the interface that determines the user experience. Instead: **does the product have any interaction surface that a human or agent operates through** — GUI, CLI, API response shape, error messages, or an agent/LLM harness. That is true for almost everything, except a purely internal library with no external interface.

- With an interaction surface → UX responsibility is by default divided across existing roles: Product (desired UX outcome), QA (existing checklist item "Usability criteria"), Reviewer (existing checklist item "Operational Readiness" extended). No new role/agent by default.
- No interaction surface (rare) → UX doesn't activate.
- A separate UX agent only when the actual complexity/stakes of that interaction surface justify it — same conditional-escalation pattern as Security above.

### Fullstack developers within bounded contexts

The preference is to organize development agents as fullstack developer agents within clear bounded contexts or other coherent work boundaries. They carry a change from technical design through implementation, tests, and relevant documentation for their bounded part.

A mandatory split between frontend and backend agents is explicitly not a starting premise. Such a split may later prove appropriate when integration complexity, scale, or domain boundaries justify it, but is not a default structure.

### Role-to-agent assignment (decided)

- One session per role per phase; no long-lived role agent. The orchestrator (see §6) starts a fresh sub-agent session per phase; hand-off runs exclusively via artifacts, never via chat memory.
- Sequential: roles work one at a time, no parallel execution (for now — no infrastructure for this in this project).
- Human/agent division: Product and Architect are agent-assisted with the human (Ties) leading; QA and Fullstack Developer are agent-owned; Reviewer is agent-owned, optionally assisted by a human engineer (not Ties) who reviews the PR directly via `gh`; merge confirmation is and remains exclusively human (Ties), never automated — see also §6.
- Identity: `role:<name>` labels (e.g. `role:product`, `role:architect`, `role:qa`, `role:dev`, `role:reviewer`) on the issue/PR the role is working on. No native GitHub assignee — the orchestrator is itself the source of truth for who works on what; a label would only make that duplicated and inconsistent.
- Context isolation: skill-based file/folder scope per role (which paths a role session may read/write), no worktree-per-role — not needed as long as roles work sequentially (one branch, one checkout at any time).

Detailed elaboration and the five roles as concrete agent specification: see [`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md).

## 5. Workflow and governance standards

The multi-agent setup must support and comply with the following existing or intended workflow practices:

| Practice | Meaning for the workflow |
| --- | --- |
| Spec-driven development (SDD) | Work starts from explicit, reviewable specifications. |
| Test-driven development (TDD) | Development work follows the red-green-refactor cycle where appropriate; tests are not an afterthought. |
| Traceability | Relations between requirements, tests, work items, and pull requests are recorded and verifiable. |
| GitHub Issues | GitHub Issues form the work-item mechanism, including Epic relations where relevant. |
| Documentation in the repository | Documentation is a standard part of the repository and of the delivery. |
| Continuous Integration | Tests and relevant checks run automatically on integration. |
| Deployments and IaC | Deployments are automated where possible; infrastructure is managed as code where possible. |
| GitHub Flow | Branch, pull request, and integration work follows GitHub Flow; project details remain authoritative. |

The exact interpretation per project, exceptions, and enforcement mechanisms are **TBD**. This PRD does not replace existing project conventions.

## 6. Orchestration, enforcement and compliance

Orchestration is a core part of the product, not just an execution detail. The orchestrator — as a responsibility, possibly later as a concrete agent or component — coordinates work across roles.

Intended responsibilities of orchestration:

- dividing work and assigning it to roles/agents within their context boundaries;
- making necessary artifacts and dependencies visible;
- guarding the prescribed order and gates;
- checking or having required evidence checked;
- escalating when evidence is missing, artifacts conflict, or a gate is not met;
- preventing an agent from unilaterally marking its own delivery as compliant or complete.

Compliance here means: demonstrably acting according to the agreed workflow, with explicit exceptions when deviating from it. The mechanism for exceptions, overrides, and audit trail is **TBD**.

### Orchestrator: decided model

The orchestrator is a concrete agent (not just a responsibility), elaborated in detail in [`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md) — an imported spec, adapted to this project on the following points:

- **Context is artifact-based, not a separate state object.** The orchestrator builds "shared context" by reading the existing artifacts (issue, `PRD.md`/`ARCHITECTURE.md` sections, `TEST-SCENARIOS.md` items, PR diff, CI results) — not by maintaining its own opaque state. Every context is therefore reconstructible by anyone (human, fresh agent, audit) from the same sources. The imported spec still spoke of a separate "shared context object"; that has hereby been replaced.
- **Escalation has a single destination**: role agent → orchestrator → human (Ties). No separate routing per role/lead as in the originally imported spec (Product Lead/Tech Lead/QA Lead/Release Manager/CTO) — this project has one human decision-maker.
- **Non-linear routing (loop-back) is allowed for rework, but phase-shortening/-skipping is not part of v1 (decided, issue #281)**: every role (Product, Architect, QA, Fullstack Developer, Reviewer) is fully involved in every change, regardless of type or urgency. CI, `pre-merge-review`, and `deploy-guards` were already never skippable; this carries the same principle through to every role — no scenario-based routing (security hotfix, refactor-only, spike, or otherwise) in v1. How much depth a change actually requires is judged by each role itself, within its own phase — that remains a judgment of the role, not an orchestrator rule. Scaling back involvement per scenario is deliberately deferred to a later version: modeling that now, without real usage data, risks overengineering the first release.
- **No automated release/merge, not even as a future extension**: merge confirmation always stays with Ties, as `WORKFLOW.md` step 4 already records. This replaces the "2.0 autoapprove" proposal from the imported spec (Dev/QA/Reviewer authorizing release themselves) — agents may autonomously advance to the *next phase* within guardrails, but never to release.

### Compliance reporting: pattern and worked example (decided, resolves §9 OQ9)

**Pattern:** reuses `WORKFLOW-ADOPTION.md`'s row-per-decision form (Change/Answer/Date/Notes), scaled to per work-item issue. Every row points to evidence that already exists (`pre-merge-review` marker, CI run, PR field) — no new report format, no separate dashboard. Orchestrator posts this as one issue comment per work item, after merge.

**Worked example**, against a real, already-completed work item from this repo (issue #265 / PR #279, `wait-for-ci.sh`) — to confirm that the pattern actually carries the right evidence links, not as a hypothetical design:

| Gate | Status | Evidence |
| --- | --- | --- |
| Discovery/Planning/Test/Implementation model recorded | ✅ | model-record markers on PR #279 (all four `claude-sonnet-5`) |
| Review: different/at-least-equally-capable model, or explicit exception | ✅ | Review marker with `same-model-exception` (only model available in this session) |
| Quality review before merge, findings in the PR | ✅ | pre-merge-review round 1 (2 findings: missing `CHANGES.md` row; duplicate `gh` calls + untested zero-checks case) and round 2 (both resolved, marker `pre-merge-review:done sha=...` on the last commit) |
| CI green | ✅ | check run linked to PR #279, itself confirmed via `wait-for-ci.sh` — dogfooding the delivered work itself |
| Traceability link 3 (PR ↔ issue) | ✅ | `Closes #265` in the PR body, `closingIssuesReferences` = 1 |
| Ties' explicit merge confirmation | ✅ | given before `gh pr merge`, per A2 |

**Established:** the pattern actually carries the right evidence links, every row points to something that already exists, and it fits in one issue comment without a separate dashboard — the remaining doubt on OQ9 has hereby been removed.

## 7. Terminology and boundaries

To keep design decisions sharp, the following terms are distinguished:

| Term | Meaning |
| --- | --- |
| Workflow | The prescribed way of developing: phases, practices, gates, and traceability. |
| Governance | Who may make which decision or check, what evidence is required, and how exceptions are handled. |
| Role | A durable responsibility, such as Product, Architect, QA, or Reviewer. |
| Agent | A concrete executor assigned one or more roles or tasks. A role is not automatically one agent. |
| Artifact | A durable, reviewable result or piece of evidence that makes work transferable and verifiable. |
| Orchestrator | The coordinating responsibility that guards work, dependencies, gates, and compliance. |
| Tooling | The technical means that enable or enforce the workflow, such as GitHub, CI, test frameworks, and deployment or IaC tooling. |
| Co-thinking session (English term, decided 2026-09-23) | A reduced-role elaboration/elicitation step (Orchestrator + Product + Architect only) for a new product or a new release/epic, before deciding to build — see §3.5. |
| Built (English term, decided 2026-09-28, from the BMad Method co-thinking session, issue #324) | A work item's PR has merged onto its release branch (`MULTI-AGENT-WORKFLOW.md`'s Workflow Execution Summary's "Release" node) — the pipeline's own output, not yet a decision about shipping it. |
| Done (English term, decided 2026-09-28, same source as Built) | The release branch itself has merged into `main` — a separate, later, always-human decision (never automatic, same as every merge-to-`main` gate this repo already has). A work item can be Built without the release it belongs to being Done. Only the two endpoint terms are adopted; BMad's own intermediate lifecycle states (ready-for-dev, in-progress, in-review, etc.) are deliberately not imported — the `role:<name>` label (A5 in `ARCHITECTURE-MULTI-AGENT-WIP.md`) already tracks that granularity, and a second mechanism for the same information would duplicate it, not add to it. Reuse this vocabulary when issue #309 (release-branch-as-workflow-tier) is scoped — this row doesn't resolve #309 itself. |

These terms must be used consistently in follow-up design. A choice of tooling must not silently determine the governance or role division.

## 8. Out of scope for this WIP

Updated 2026-09-21: five of the original seven points have now been (partially) decided
elsewhere in this document or in `ARCHITECTURE-MULTI-AGENT-WIP.md` — the end of this section
says where. What still remains fully open:

- a concrete implementation stack, model choice, or vendor choice;
- a fixed frontend/backend or other technical team split;
- the precise technical implementation of the permission and memory mechanism (the
  *principle* — skill-based file scope, no state outside artifacts — is
  decided, see A1/A4 in `ARCHITECTURE-MULTI-AGENT-WIP.md`);
- a concrete GitHub template structure for Issue/PR templates (the `role:<name>` label
  is decided, see A5; §3.4 explicitly notes that concrete template field placement
  is not yet recorded here);
- a worked-out minimal test catalog per security trigger category (the trigger list
  itself is decided, see §9 OQ5).

What originally stood here and has now been (partially) decided elsewhere: definitive
agent architecture/number of agents (`ARCHITECTURE-MULTI-AGENT-WIP.md` Decision 3, §4 five
roles + orchestrator); UX role shape (§9 OQ7, fully decided); QA/Reviewer role shape
("Core responsibilities per role" above).

## 9. Open questions / TBD

Status per question: **decided**/**partially decided** refers to a concrete decision above or in [`ARCHITECTURE-MULTI-AGENT-WIP.md`](ARCHITECTURE-MULTI-AGENT-WIP.md)/[`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md); the rest remain **open** — none of these have been implicitly answered.

1. Which artifacts are minimally required per workflow phase, and which relations must be machine-readable for traceability? — **partially decided**: artifacts per granularity level are recorded in §3.4; the reference process (requirement → PR) with an artifact per phase is in `MULTI-AGENT-WORKFLOW.md`. The machine-readable relation remains the existing `Covers:` token; no new mechanism introduced.
2. Which gates are mandatory before work may move to the next phase, and which role or automation assesses each gate? — **decided**: gate/role per phase follows the reference process in `MULTI-AGENT-WORKFLOW.md`, with CI/`pre-merge-review`/`deploy-guards` as never-skippable gates (see "Orchestrator: decided model", §6).
3. How is context isolation shaped technically and organizationally, including access to the repository, GitHub, and the deployment environment? — **decided**: skill-based file/folder scope per role (see "Role-to-agent assignment", §4), no OS sandboxing, no worktree-per-role.
4. How are bounded contexts or other work boundaries established and changed? — **decided** (21-09-2026): a bounded-context choice is an architecture decision like any other, recorded as `## Decision N` in `ARCHITECTURE-MULTI-AGENT-WIP.md`. The change trigger reuses `refactoring-triggers`. Who may propose it and what happens to work in progress: see `ARCHITECTURE-MULTI-AGENT-WIP.md`, "Proposing a boundary change mid-work" — no synchronous escalation, a non-blocking issue + async triage question to Ties; work in progress finishes against the old boundary.
5. Which security tests and risk classifications are minimally required, and when is a separate Security agent justified? — **decided** (21-09-2026): see "Security as an explicit responsibility" above — risk-driven trigger list (auth, secrets, deploy/CI config, IaC, sensitive data, untrusted input), embedded in Reviewer's role-contract skill, no new taxonomy, plus a POLP-organized minimal test catalog per trigger category (same subsection).
6. Which verifications are expected from Product and Architect besides QA and Reviewer, and how is overlap deliberately managed? — **decided** (21-09-2026): see "Core responsibilities per role" above — every role answers a different question; legitimate conflict escalates, it isn't suppressed. Both concrete overlaps resolved (see "Overlap 1"/"Overlap 2" in the same subsection): QA determines test strategy + scenario, Fullstack Developer writes the actual failing test; `check-traceability.sh` verifies structurally, Reviewer verifies semantically.
7. Is a UX design role needed? If so, which artifacts and gates should that role own or assess? — **decided**: see "UX as a conditional responsibility" above — the activation rule is not "is there a UI" but "does the product have any interaction surface" (GUI, CLI, API, or an agent/LLM harness); by default divided across existing roles, a separate agent only for justified complexity/stakes.
8. Which orchestrator tasks are automated, which require human decision, and how are exceptions recorded? — **decided**: see "Orchestrator: decided model", §6.
9. How is compliance reported without the workflow becoming unnecessarily slow or bureaucratic? — **decided** (21-09-2026): see §6, "Compliance reporting: pattern and worked example" — the `WORKFLOW-ADOPTION.md` pattern, plus a worked example against a real, completed work item (#265/PR #279) that confirms the pattern carries the right evidence links.
10. How does this design connect to existing workflow documentation, existing repositories, and their own conventions? — **decided**: reuses existing skills/hooks (`WORKFLOW.md`, `write-spec`, `pre-merge-review`, `deploy-guards`, `tdd-seams`, `check-traceability.sh`) unchanged; the new role/orchestration layer comes in its own skill, not a replacement.
11. **OQ11 — Which release does this land in?** (added 2026-09-26, in English — the header table's "Target release: TBD" field, referenced elsewhere in this document but never previously registered here) — **open, Ties' explicit call**: stays open until the multi-agent workflow has run end-to-end on one real work item and the result is good enough to kick off implementation/integration into `main` — see issue #294.

## 10. Proposed follow-up scope

Updated 2026-09-21: the reference process (requirement → PR, with an artifact per phase)
that previously stood here as the "next design step" now already exists —
`MULTI-AGENT-WORKFLOW.md`'s pipeline, "Workflow State & Context Management," and the
Standard Workflow Path diagram cover that. Four of the six follow-up points below have,
for the same reason, also already been (partially) decided. The step that actually
remains is narrower:

1. **Close OQ9**: run the existing reference process against one real work item,
   end-to-end, to confirm the compliance-reporting pattern actually works
   as described — no separate new design, just the missing example. (OQ4, OQ5
   and OQ6 were fully decided on 21-09-2026 — see §9.)
2. After that: request §11 acceptance.

Original follow-up points and where they now (partially) land: an artifact and
traceability model (decided, §3.4 + the reference process); a role-/agent-assignment model
and context boundaries (decided, §4 + A4); orchestration and compliance controls (decided,
§6 + OQ9's pattern); a proposal for UX (fully decided, OQ7). Genuinely remaining follow-up
scope: a gate and evidence catalog in detail, and the risk-based security testing approach
(coincides with OQ5 above).

Every follow-up proposal must first be tested against the design principles in this document and may not be treated as definitive architecture before it has been explicitly decided.

## 11. Acceptance of this PRD

Updated 2026-09-21: acceptance applies to this PRD **together with**
[`ARCHITECTURE-MULTI-AGENT-WIP.md`](ARCHITECTURE-MULTI-AGENT-WIP.md) and
[`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md) — not just this document. The
architecture decisions and invariants (A1-A11, as of 2026-09-25) now largely live in those two
files, not here; acceptance of this PRD alone would not cover them.

This trio of documents is ready to serve as an attachment or reference for a GitHub Epic once stakeholders confirm that it:

- correctly represents the intended direction and premises;
- leaves open design decisions visibly marked as **TBD** (or **partially decided**, with what's still missing explicitly named — see §9);
- records every implementation/architecture choice as an explicit, dated decision — no choice is made silently (this is sharper than "introduces no choices": a worked-out architecture document does contain choices, the requirement is that all of them are traceably decided, not that there are none);
- offers a sufficient basis to formulate separate, traceable follow-up work items.

**Current status (updated 2026-09-23).** Ties confirmed acceptance on 2026-09-21 — see `wip/multi-agent-development/
DIRECTION-CHECK-SUMMARY.md`. OQ11 (target release timing) stays deliberately open,
resolved only once the process has run end-to-end on one real work item. Follow-up work
items are now being drafted (§3.5's co-thinking session, applied first to the plugin
conversion initiative in `wip/claude-code-plugin/`), consistent with that acceptance.

