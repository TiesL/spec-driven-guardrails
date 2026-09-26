# Multi-Agent Workflow — Direction Check

Management summary of `PRD-MULTI-AGENT-WIP.md`, `ARCHITECTURE-MULTI-AGENT-WIP.md`, and
`MULTI-AGENT-WORKFLOW.md` (epic #65), written to support the PRD §11 direction-check
decision. Doubles as a standalone intro to the multi-agent workflow direction for a person
or agent who hasn't read the three source documents.

**Direction confirmed by Ties (2026-09-21).** See "Status" below for what that does and
doesn't close.

## Purpose

This is a directional specification (epic #65, WIP exploration) for extending this repo's own single-agent development workflow to a **multi-agent model**: several specialized agents collaborating on one change, instead of one agent doing everything.

The problem it addresses: without an explicit collaboration model, multiple agents can interpret the same context differently, skip or duplicate responsibilities, treat work as "done" without independent evidence, follow the agreed workflow only partially, and lose decisions to chat instead of durable artifacts. The proposal is not "more agents" for its own sake — it's a development *system* where work, decisions, checks, and handoffs are all reconstructable from shared artifacts (issues, PRs, PRD.md/ARCHITECTURE.md, TEST-SCENARIOS.md, CI), not from memory or chat.

## The model

One **orchestrator** (a persistent session) dispatches a fresh sub-agent per phase, through a fixed five-role pipeline. Work moves forward, or loops back to an earlier phase for rework — v1 has no other branching.

| Role | Answers |
| --- | --- |
| Product | Is the requirement itself correct and complete? |
| Architect | Does the design satisfy the requirement and the architecture principles? |
| QA | What needs testing, what kind of test, and does the implementation behave accordingly? |
| Fullstack Developer | Build it — including the actual test code, red-before-green, per QA's strategy. |
| Reviewer | Independent final gate: is there evidence this all really happened, and is the result good code? |

Each role hands off through a real, durable artifact (an issue, a PR, a commit, a doc section) — never through memory the orchestrator holds itself. A genuine disagreement between two roles goes to Ties with both sides' findings shown verbatim, side by side — never an orchestrator-authored summary.

## Key decided principles

- **No phase-skipping in v1.** Every role engages fully on every work item, even a trivial one. Scaling the process down for small items is deliberately deferred to a later version, so v1 stays simple and predictable rather than half-building a triage layer.
- **Escalation is asynchronous, not blocking.** A role that spots a needed boundary change (spec gap, architecture conflict) does not halt and wait for Ties mid-work. It opens a non-blocking issue and asks Ties, async, whether to pick it up next, leave it for later, or close it. In-flight work finishes under the old boundary.
- **Context isolation.** Each phase runs as a fresh sub-agent, not a continuation of the previous role's session. This forces every handoff through a durable artifact (issue, PR, doc) instead of carried-over chat memory — the same discipline this repo already applies to its own single-agent workflow.
- **Human-only merge.** No role, including the orchestrator, merges a PR. That stays Ties' explicit action, unconditionally — mirrors the existing GitHub Flow rule in this repo's `CLAUDE.md`.
- **Escalation on disagreement shows both sides verbatim.** When two roles genuinely disagree, Ties sees each side's actual findings side by side — never an orchestrator-authored summary that could flatten or bias the disagreement.
- **Security is an explicit, shared responsibility**, organized around the Principle of Least Privilege (POLP) as the baseline for what gets tested and how access is scoped — not bolted on only at Review.

## Governance and compliance

Conformance isn't taken on faith — it's checked against the same durable artifacts every handoff already produces:

- **Model-choice recording.** Every stage (Product, Architect, QA, Developer, Reviewer) records which model and reasoning effort it ran with, always, in the issue/PR/findings comment — not only when the choice is non-obvious. This makes cost/capability tradeoffs auditable after the fact.
- **Independent review, not self-certification.** The Reviewer role is a separate agent instance from whoever implemented the change, checking both traceability (does the code match what was specified) and code quality (abstractions, reuse, efficiency) — the same split this repo's existing `pre-merge-review` skill already enforces for single-agent work.
- **Structural checks stay automated; judgment stays with a role.** Scripts like `check-traceability.sh` verify links exist (F↔S/R↔T references present) but never judge whether a link is *semantically* correct — that's the Reviewer's call, explicitly, so automation doesn't quietly absorb a judgment it can't actually make.
- **A worked example already exists.** OQ9's compliance-reporting walkthrough was built against a real, already-completed work item from this repo (issue #265 / PR #279), not a hypothetical — so the reporting shape has been sanity-checked against actual output, not just designed on paper.

## Status

**Decided, as of this document:**

- The five-role pipeline and orchestrator model (no phase-skipping in v1)
- Escalation paths (boundary changes: async issue + triage question; disagreements: verbatim to Ties)
- Context isolation via fresh sub-agents per phase
- Human-only merge
- Role scope split, including the QA/Reviewer overlap resolutions
- The security testing approach (POLP-organized)
- Model-choice recording as a mandatory, always-on practice

All four originally-partial open questions (spec gap escalation, security test scope, QA/Reviewer overlap, compliance reporting) are now fully closed. `ARCHITECTURE-MULTI-AGENT-WIP.md`'s "still open" section is empty.

**Still open:** target release timing (OQ11). Ties' explicit call: OQ11 stays open until the multi-agent workflow has run end-to-end on one real work item and the result is good enough to kick off implementation/integration into `main` — OQ11 is resolved by that run, not before.

**Where this sits:** PRD §11 is the actual go/no-go gate for this whole direction. **Ties has confirmed the direction** — the model, principles, and governance described above reflect what he wants. This unblocks PRD §10's next step (below); it does not itself resolve OQ11.

## The direction-check ask

PRD §11 asked one question before any follow-up work gets drafted: does this direction actually reflect what Ties wants — five specialized roles plus an orchestrator, context-isolated handoffs, async (non-blocking) escalation, human-only merge, and POLP-organized security. **Answer: yes, confirmed 2026-09-21.**

Next step per PRD §10: run this process against one real work item end-to-end (the OQ9 example already gives a head start). OQ11 (release timing) is decided by the outcome of that run.
