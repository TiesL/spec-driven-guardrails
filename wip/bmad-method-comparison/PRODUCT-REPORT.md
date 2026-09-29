Model/effort: Claude Sonnet 5, medium reasoning effort, Product role.

# Product report — BMad Method comparison (issue #324)

Co-thinking session (Orchestrator + Product + Architect only, per
`wip/multi-agent-development/PRD-MULTI-AGENT-WIP.md` §3.5). This is Product's
report; Architect's follows separately. Nothing here is promoted into
`PRD.md`/`ARCHITECTURE.md`/`wip/multi-agent-development/` until Ties explicitly
accepts it.

**Method note.** I did not run `grilling`'s live interview — Ties isn't
available in this run (per this session's role brief). Instead §4 states each
open question, a recommended answer, and confidence, following the skill's
design-tree/frontier framing as closely as a non-interactive report allows.

---

## 1. Problem framing

BMad and this repo's multi-agent workflow (on `release/295-multi-agent-workflow-v1`,
not yet merged — hereafter "v1") solve overlapping problems from different starting
points. BMad optimizes a **single agent doing a bounded chunk of work well**, with
reviewers bolted on around it. v1 optimizes **five specialized roles each answering
a different question**, with human authority preserved at every gate. Both are
evidence-based, both refuse self-certification, both keep humans in charge of
merge. Where they diverge is where BMad points at gaps this repo doesn't yet serve
well.

### 1.1 Sizing discipline has no home in v1

BMad's Build a Change is explicit about scope: "Use the smallest amount of BMad
that safely fits the change... about 500 lines of code," "each run stays focused
on one goal," unrelated findings go to `deferred-work.md` rather than being fixed
inline. This repo has no equivalent judgment surfaced anywhere. `ROLE-DESCRIPTIONS.md`
does the opposite in one respect that's directly load-bearing here: v1's
"Engagement: full, always" (issue #281, `MULTI-AGENT-WORKFLOW.md` §2) commits to
**all five roles fully engaging on every change, regardless of type or urgency**,
with scenario-based routing explicitly deferred to v2 (`PRD-MULTI-AGENT-WIP.md` §6,
`ROLE-DESCRIPTIONS.md`'s "No scenario-based exception routing in v1"). Issue #307
(the v2 backlog) already records the resulting cost as an *unplanned* finding, not
a designed constraint: "pipeline round-trip/ceremony cost... #296: ~3 review
rounds, ~10.5h; #299: ~2 rounds, ~2h." That's real evidence a fixed five-role
minimum doesn't scale down to small changes — exactly the gap BMad's "smallest
amount that safely fits" rule targets directly, and exactly the gap A3's escape
hatch (`ARCHITECTURE-MULTI-AGENT-WIP.md`) was invented ad hoc to patch, once,
messily (per #307: "narrowing three roles at once... attribution of which skip
caused which defect was muddled").

### 1.2 Deferred findings have a place to go, but no disposal contract

Both systems agree that findings unrelated to the current change shouldn't be
fixed inline. BMad names this explicitly (`deferred-work.md`) *and* names who
decides what happens to a deferred finding next: "the orchestrator has to decide
what happens next: create a ticket, append to a central queue, correlate
duplicates across runs, or do nothing." This repo's Reviewer/QA finding format
(`ROLE-DESCRIPTIONS.md` "Shared, across all five roles" — summary, failure
scenario, location, category, CONFIRMED/PLAUSIBLE) defines the *shape* of a
finding but not its *disposition*. In practice this repo already improvises the
answer ad hoc — issue #307 itself is exactly "append to a central queue" — but
that pattern isn't written down as a rule anywhere; it's an observed regularity
across three pilots, not a decided mechanism.

### 1.3 No epic-level retrospective mechanism exists

Finish an Epic's `bmad-retrospective` reads the whole epic's diff/commits/plans as
one review after all tickets are done, and produces a verdict (accepted /
accepted-with-open-items / rejected) grounded in "what the diff, the commits, and
the plans actually show" — not individual recollection. This repo has nothing at
that granularity. `pre-merge-review` operates per-PR; `WORKFLOW-ADOPTION.md`
tracks per-project adoption of workflow changes; nothing looks at an entire epic's
worth of merged work as a single unit and asks "did this epic, in aggregate, do
what it said it would, and did architecture drift across its work items?" Epic
#295 itself is a live case where this gap is visible: issue #322 exists precisely
because defects accumulated across W1-W4's individual PRs (#320, #319, #318,
#317) went unnoticed as a *pattern* until someone manually aggregated them before
the release→main merge. A `bmad-retrospective`-shaped mechanism would have
surfaced that aggregation automatically, as an epic-closing gate rather than an ad
hoc cleanup issue.

### 1.4 No standing definition of what "review scope" should be at different depths

BMad's Review a Change explicitly names two depths — "thorough" (parallel
multi-lens reviewers) vs. "quick" (single reviewer) — as a deliberate choice, not
an accident of who's available. This repo's Reviewer role and `pre-merge-review`
both scale "proportional to the PR" in spirit (`pre-merge-review`'s own
description says "scope proportional to the PR") but v1's Reviewer is a single
role/agent, not a swappable roster of independent lenses. This is adjacent to
1.1 (sizing) but distinct: even at full five-role engagement, there's no BMad-style
menu of *how many independent review angles* a given PR gets.

### 1.5 Multi-perspective *adversarial* review is untried here

BMad's reviewer subagents (Blind Hunter, Edge Cases Hunter, Verification Gap
Finder) and the "Code Review Crew"/"Anti-Consensus Club" personas are built
specifically so that *separate model instances* disagree productively — "one
model voicing five personas tends to make them agree... separate agents keep
their reasoning independent, which is the point." v1's Reviewer role is a single
gate (deliberately — see Non-adoptions §3 on Reviewer-splitting) but the
*Party-mode* pattern (multiple independent personas in one conversation, human
steering) has no analogue anywhere in this repo, including outside the formal
pipeline — there's no lightweight way to stress-test a plan or a design decision
against several adversarial viewpoints before committing resources to the full
five-role pipeline.

### 1.6 Release-branch tier is informal exactly where BMad has a named concept

BMad's ticket hierarchy (Initiatives → Epics → Entries, with `tickets.toml`
tracking and "the user or orchestrator decides when to mark it done" separate from
build status) maps loosely onto this repo's Epic → Work item structure, but BMad's
distinction between "built" (shown in review) and "done" (a human/orchestrator
call) is sharper than anything written down here. More concretely: issue #309
("Introduce release branches as a workflow tier") is *exactly* the gap between
BMad's Epic tier and this repo's current two-tier `main`/`feature` model — #309
documents that `release/295-multi-agent-workflow-v1` was created ad hoc, works
mechanically, but "exists only in one conversation, not in `CLAUDE.md` or any
skill." BMad's docs don't resolve this for us (its own tiering is oriented around
tickets, not branches), but the *problem* BMad's structure implies — a named
intermediate tier between individual work items and top-level delivery — is
already an open, unaddressed issue in this repo, independently surfaced.

### 1.7 No standing "fresh chat, no context contamination" discipline for a single-agent build

BMad's Build a Change insists on starting fresh specifically to avoid the
"I just built this and it works" bias `pre-merge-review` already guards against
for review (`context: fork`). But this repo's guard against self-certification
bias is currently applied only at the Review gate, not at earlier stages —
e.g. nothing stops Architect's own session, still warm from writing a design, from
also being the one that assesses whether Fullstack Developer's plan matches that
design, or QA grading its own scenario coverage without a fresh read. v1's role
model (`PRD-MULTI-AGENT-WIP.md` §4, "Rol-naar-agent toewijzing") already decides
"one session per role per phase, no long-lived role-agent," which structurally
achieves most of this — but it's not framed as a *named principle* the way BMad
frames it, so a future skill change could erode it without anyone noticing the
regression.

---

## 2. Candidate ideas, prioritized

Ordered by expected value against effort-shape; ties broken toward ideas that
close a gap already independently visible in an open issue (cheaper to justify,
lower risk of being solution-in-search-of-problem).

### 2.1 A named "escape hatch" contract for scenario-based scope reduction (small)

**What:** Formalize A3's escape hatch (currently a one-off, loudly-logged,
Ties-authorized deviation) into a small, explicit decision procedure Product/
Architect/whoever-is-orchestrating can invoke *before* starting a work item, not
only mid-flight: given a change's rough size/risk, is full five-role engagement
warranted, or does a named, single-role-at-a-time narrowing apply? Not
BMad's automatic size threshold (500 lines) — that number is a BMad-specific
convention, not evidence this repo should copy a number — but the *shape* of
BMad's judgment ("use the smallest amount that safely fits") stated as a
repeatable question instead of an ad hoc exception each time.

**Why it matters:** #307 already has two backlog items pointing at exactly this:
the A3 escape hatch has "only been used once, narrowing three roles at once...
attribution of which skip caused which defect was muddled," and the backlog
explicitly wants "a cleaner v2 data point: use the hatch again with exactly one
role narrowed at a time." This candidate *is* that data-point-generating
mechanism, formalized rather than left to happen accidentally on the next pilot.
It also directly answers the round-trip-cost finding in #307 (~10.5h for the
#296 pilot) by
giving small changes a cheaper path without abandoning full engagement for
changes that need it.

**Effort shape:** Small — this is a decision-procedure/skill-text change (a
"when does A3 apply, and how is it invoked deliberately rather than reactively"
addition to `MULTI-AGENT-WORKFLOW.md`/a new short skill), not new infrastructure.
Estimating the actual effort belongs to Architect.

**Touches:** `ARCHITECTURE-MULTI-AGENT-WIP.md` (A3), `ROLE-DESCRIPTIONS.md`
("No scenario-based exception routing in v1" — this candidate does NOT propose
removing that decision; it proposes a formal, opt-in, per-instance procedure for
invoking the *already-existing* escape hatch, not a new standing routing
category), issue #307's two backlog items.

### 2.2 Deferred-finding disposition rule (small)

**What:** Write down, once, the rule this repo already follows informally: a
finding unrelated to the current change's scope is either (a) turned into its own
issue immediately if actionable and small, (b) appended to a holding-pen epic like
#307 if it's part of a recognized backlog theme, or (c) explicitly dismissed with
reasoning recorded — never silently dropped, never fixed inline without a
scope-expansion decision. BMad's own three-way split (create ticket / append to
queue / do nothing, each an explicit orchestrator call) is a reasonable template,
adjusted for the fact this repo's Reviewer/QA finding format (summary, failure
scenario, location, category, CONFIRMED/PLAUSIBLE) already has almost everything
needed except the disposition field.

**Why it matters:** closes 1.2 above. Low-cost because it's naming an existing
practice, not inventing one — the risk of *not* doing it is drift (the next
pilot improvises a fourth disposition path nobody agreed to).

**Effort shape:** Small — a short addition to `ROLE-DESCRIPTIONS.md`'s "Shared,
across all five roles" section (the finding-format paragraph already exists;
this adds one more required field/decision).

**Touches:** `ROLE-DESCRIPTIONS.md` finding-format section; no conflict with
anything decided — pure completion of an already-decided but incomplete
mechanism.

### 2.3 Epic-closing retrospective gate (medium)

**What:** A retrospective step that runs once every work item under an epic is
closed (built/done/dropped, matching BMad's own definition of "finished"),
reading the epic's aggregate diff/commits/plans/PRs as one review — not asking
individual role-agents to recall what happened, but reading the evidence, the way
`pre-merge-review` already treats evidence over self-report at PR scope. Verdict
shape borrowed from BMad almost directly because it fits this repo's own
evidence-over-assertion principle (PRD §3.3) without modification: accepted /
accepted-with-open-items / rejected, with an unfinished-work-item epic defaulting
to "rejected" unless Ties overrides.

**Why it matters:** issue #322 is live proof this gap costs real time right now —
four defects (#320, #319, #318, #317) accumulated across epic #295's work items
and had to be manually aggregated into a single pre-merge cleanup issue because
nothing caught the pattern earlier, at the point each defect's own PR merged. A
standing epic-retrospective gate would have run at whatever point W1-W4
individually closed and flagged the pattern (e.g. #319's mawk-regex bug affecting
both `compliance-evidence.sh` and `role-label-staleness.sh` — a cross-work-item
architectural-drift signal exactly like what BMad's retrospective looks for:
"aggregate defects across tickets, architectural drift/duplication"). This also
gives OQ11 (issue #294) a repeatable mechanism instead of a one-off manual
judgment each time a pilot needs release-readiness assessed.

**Effort shape:** Medium — needs a new role-dispatch shape (who runs it: existing
Reviewer role extended, or a sixth invocation of Product+Architect+QA+Reviewer
together reading aggregate evidence — genuinely Architect's call), plus deciding
where its output lives (a new `EPIC-RETROSPECTIVE-<n>.md`? an issue comment on
the epic issue, following the `WORKFLOW-ADOPTION.md` row-pattern precedent
§6's compliance-reporting example already established?). Not small because it's a
new gate in the pipeline, not a text clarification.

**Touches:** `ROLE-DESCRIPTIONS.md` (does this become a Reviewer extension, or a
new standing responsibility?), `MULTI-AGENT-WORKFLOW.md`'s Workflow Execution
Summary (a new terminal step after "Release"), issue #322 (this candidate
would have caught #322's defects earlier had it existed), issue #307 (the
"performance — pipeline round-trip cost" NFR item this partially trades off
against — a retrospective is itself more ceremony, weighed against less
end-of-epic cleanup).

### 2.4 Named review-depth tiers, mirrored from BMad's "thorough"/"quick" (small-medium)

**What:** Give Reviewer (and, by extension, `pre-merge-review`) an explicit,
named choice of review depth tied to change size/risk — analogous to, not copied
from, BMad's thorough (parallel independent reviewer lenses) vs. quick (single
reviewer) split. For this repo that would most naturally mean: a "quick" PR gets
the existing single-Reviewer-role review; a "thorough" PR (touching more of the
change surface, or explicitly flagged high-risk) dispatches a small number of
independent lens-agents alongside Reviewer, each producing its own finding set
per the existing minimal-finding-content structure, before Reviewer's own final
gate.

**Why it matters:** `pre-merge-review`'s own description already claims "scope
proportional to the PR" as a design goal — this candidate makes that claim
mechanically true rather than aspirational, and gives it the same
evidence-over-self-report backing every other gate in this repo has. It's a
closer BMad parallel than 2.3, and the "why" is directly BMad's own reasoning —
independent model instances catch different blind spots than one instance
reviewing itself, even a fresh-context one.

**Effort shape:** Small-medium — the finding format, evidence discipline, and
fork/fresh-context pattern all already exist (`pre-merge-review`'s
`context: fork`); what's new is a size/risk classifier and dispatching more than
one reviewer instance for the "thorough" case. Architect should size this against
whatever session/dispatch machinery v1 already has for spawning fresh sub-agent
sessions per role.

**Touches:** `pre-merge-review` skill directly, `ROLE-DESCRIPTIONS.md` Reviewer
entry (still "stays a distinct role, never merged into QA or Fullstack
Developer" — this candidate adds depth *within* Reviewer's gate, doesn't split
Reviewer into multiple standing roles — see Non-adoption §3.2 for why that
distinction matters).

### 2.5 Lightweight adversarial-discussion mode for pre-decision elaboration (medium)

**What:** A BMad-Party-mode-inspired pattern usable *within* a co-thinking
session (or even standalone, before one starts) — a small number of adversarial
personas (e.g. "what's the cheapest way this breaks," "what did we just agree on
that contradicts an earlier decision," "is this actually necessary or are we
solving an imagined problem") reviewing a Product or Architect draft before it's
finalized, with Ties steering. Not a standing role — a tool a co-thinking session
can invoke.

**Why it matters:** this repo already has an informal version of this idea —
the "blameless retrospective — one fresh reviewer per role plus the
orchestrator's own self-assessment" pattern used for the plugin-conversion pilot
(`PRD-MULTI-AGENT-WIP.md` §3.5, "Pilot findings incorporated"). That pattern
worked and produced real process fixes (A7, A8, A9). BMad's Party mode is a more
general, reusable version of the same instinct: separate agents disagreeing
productively, human steering, never autonomous. Formalizing it as a repeatable
pattern (rather than a one-off retrospective structure invented for one pilot)
would make it available earlier — during Product/Architect elaboration itself,
not only after a pilot concludes.

**Effort shape:** Medium — mostly a new skill/pattern document (how personas are
chosen, how dispatch works, how findings get reconciled back into the
co-thinking session's report), no new infrastructure since sub-agent dispatch
already exists for the role pipeline.

**Touches:** `wip/multi-agent-development/PRD-MULTI-AGENT-WIP.md` §3.5
(co-thinking sessions), does not conflict with anything decided — it's additive
tooling *for* Product/Architect, not a new role.

### 2.6 "Built" vs. "done" as a named distinction, reused for the release-branch tier question (small, feeds #309)

**What:** Adopt BMad's sharp separation — "a build finishes at built... the user
or orchestrator decides when to mark it done. A tracker card's status remains
separate from build status" — as explicit vocabulary in this repo, and use it to
help resolve #309's open release-branch-tier question: a work item merging into
`release/295-multi-agent-workflow-v1` is "built"; the release branch merging into
`main` is "done." This gives #309 borrowed vocabulary rather than a borrowed
mechanism (this repo's actual tiering stays GitHub-Flow-branch-based, not
`tickets.toml`-based — see Non-adoption §3.4).

**Why it matters:** #309 is already open and already describes exactly this gap
in different words ("Ties reviewing/approving each work item's PR but wanting the
final promotion to `main` to be a single, separate, explicit decision"). This
candidate doesn't solve #309 (that's Architect/Product's job when #309 is
actually scoped) — it hands whoever scopes #309 a precise, already-battle-tested
distinction to reuse instead of reinventing the built/done split from scratch.

**Effort shape:** Small — vocabulary/documentation, feeds directly into #309's
existing scope rather than opening new scope.

**Touches:** issue #309 directly (should be referenced when #309 is picked up),
no PRD/ARCHITECTURE change of its own.

---

## 3. Explicit non-adoptions

### 3.1 BMad's single-primary-agent model (bmad-build doing investigate → plan → implement → review → commit)

**Not recommending.** This is BMad's central architecture and it's a genuine,
reasoned *disagreement*, not just a fit mismatch: v1's five-role split exists
specifically so that "is the requirement right" (Product), "is the design right"
(Architect), "does it work as intended" (QA), "is there evidence it actually
happened" (Reviewer) are answered by different sessions that can't share each
other's blind spots or self-certify. BMad achieves a version of this only at the
review phase (independent reviewer subagents), with one agent doing everything
upstream of that. Collapsing v1 back toward a single build agent would undo the
entire premise of epic #65, which is itself grounded in this repo's own dogfooded
evidence (`PRD.md`: "across four projects and 27 merged PRs: **zero** PRs
reference an issue, **zero** have a review, **zero** scenarios have a coverage
field" — self-review by the same actor that built the thing is the exact failure
mode this repo was built to prevent, generalized). Not a rejection of BMad's
craft; a rejection of importing its unit of work when this repo has already
decided, with evidence, that the unit of work should be smaller and more
separated.

### 3.2 Splitting Reviewer into multiple standing named-persona roles (Blind Hunter, Edge Cases Hunter, Verification Gap Finder as permanent roles)

**Not recommending as standing roles** (2.4 above proposes the *capability*
without the standing headcount). `ROLE-DESCRIPTIONS.md` already made this call
explicitly for QA/Fullstack Developer/Reviewer: "Stays a distinct role, never
merged into QA or Fullstack Developer" — the existing five-role split is already
a deliberate, reasoned decomposition; multiplying reviewer personas into
permanent roles adds process weight symmetric to the problem 1.1 names (ceremony
cost, #307), for a benefit BMad gets mostly from *the reviewer never having
written the code* — a property v1's Reviewer already has via fresh-context
dispatch. The persona-multiplication is BMad's answer to being a single-agent
system with only one review pass; it's solving a problem v1 doesn't have in the
same shape.

### 3.3 Autonomous-loop mode (`bmad-build-auto`) as a v1 capability

**Not recommending now**, and possibly never for this repo's actual usage
pattern. BMad's autonomous loop is carefully guardrailed (never marks a ticket
done, halts on intent gaps, requires clean tree, orchestrator explicitly selects
which tickets run) — a genuinely well-designed feature. But it solves a problem
this repo doesn't currently have: batch-running many small, already-refined
tickets unattended. v1's actual usage so far (three pilots: #296, #299, #302) is
Ties-in-the-loop the entire way, on one work item at a time, and `WORKFLOW.md`
step 4 ("wait for TiesL's explicit confirmation... never merge automatically")
plus `MULTI-AGENT-WORKFLOW.md`'s "merge/release stays human-only, permanently,
with no future auto-approve exception" already forecloses the part of autonomy
BMad's loop is built to enable (moving toward less human touch per ticket). If
this repo's ticket volume grows enough that unattended overnight loops become
genuinely valuable, that's a distinct future decision — not something today's
evidence supports building toward.

### 3.4 `tickets.toml` / three-tier Initiative-Epic-Entry tracking file format

**Not recommending.** This repo's tracking is GitHub Issues + `PRD.md` +
`TEST-SCENARIOS.md`, deliberately chosen so a BA/PO/PM reader can trace a PR
backward through GitHub's own UI without needing repo-specific tooling (README.md
§"Who it's for" — the UAT trace-back use case is explicitly a *design goal*, not
an accident). Introducing a parallel `tickets.toml`-style file would duplicate
what GitHub Issues + `Covers:` tokens already do, conflicting with
`check-traceability.sh`'s single source of truth and this repo's explicit
anti-goal of building "an agent framework" with its own state format
(README.md "Who it's for and who it's not"). The *vocabulary* (2.6, built vs.
done) is worth borrowing; the file format is not.

### 3.5 BMad's ecosystem/tool-integration breadth (Cursor, other IDEs, "BMad Ecosystem" section)

**Not evaluated, not recommended for consideration in this session.** This repo
is explicitly Claude-Code-specific by design (README.md "Known limitations":
"skills are Claude Code skills specifically — not provider-agnostic today").
BMad's cross-tool ambitions aren't a gap this repo has — they're a different
product goal this repo has already, deliberately, declined to pursue.

---

## 4. Open questions for Ties

Presented as a frontier — each is a genuine judgment call, not a fact I could
look up myself (per A10). Recommended answer stated with confidence; low-confidence
ones are flagged as such rather than dressed up as settled.

---

**Q1 — Should the A3-escape-hatch formalization (candidate 2.1) happen before or
after epic #295/OQ11 (issue #294) actually closes?**

Candidate 2.1 directly targets #307's own stated desire for "a cleaner v2 data
point" from the escape hatch, and #307 is explicitly v1's *deferred* backlog, not
in-scope for OQ11. But OQ11's gate (issue #294, 2026-09-27 note) is now looser
than originally scoped — "Ties judges when accumulated progress is 'enough.'"

➡️ **Recommend: after.** #294's gate criterion already treats W1-W4 progress as
sufficient without a fresh pilot; layering a new escape-hatch procedure onto a
still-open v1 risks conflating "does the *existing* five-role pipeline work" with
"does a *new* scope-reduction mechanism work," muddying OQ11's own evidence the
way #307 already flags A3's one actual use case did. Confidence: medium-high —
this is mostly sequencing hygiene, not a real disagreement about the idea's
value.

---

**Q2 — Does the epic-closing retrospective (candidate 2.3) apply retroactively to
epic #295 itself, specifically to close out issue #322?**

#322 is functionally already doing part of a retrospective's job by hand — it's
"one entry point covering all of them" for #295's known defects before the
release→main merge. If 2.3 gets built, running it once against #295 itself would
both validate the mechanism against real, already-known findings (a known-answer
test) and potentially close #322 with less manual aggregation than it currently
requires.

➡️ **Recommend: yes, if 2.3 is picked up before #322 is otherwise resolved by
hand** — same dogfooding instinct issue #294 already uses (test the mechanism
against real work, not a synthetic case). If #322 gets manually closed first
(likely, given it's already in progress and blocks the release merge), 2.3 should
still be validated against #295's history retrospectively as its first real test
case, even after the fact. Confidence: medium — depends on #322's actual timeline,
which I don't have visibility into from this session's evidence.

---

**Q3 — Should candidate 2.4 (named review-depth tiers) be scoped as part of v2
(#307) or as a smaller, immediate `pre-merge-review` skill change?**

`pre-merge-review` already claims proportional scope as a design goal but doesn't
mechanize it. This could be a quick skill-text tightening now, or a v2-epic item
alongside the other backlog entries in #307.

➡️ **Recommend: v2 (#307)**, specifically because "dispatching more than one
reviewer instance" has real ceremony-cost implications that #307's own
"pipeline round-trip/ceremony cost" NFR item is already tracking — bundling this
with that existing cost-awareness thread avoids introducing a new source of the
same problem #307 already flags, unexamined. Confidence: medium — a low-risk
version (classifier + optional second reviewer, no new infrastructure) could
plausibly ship smaller and sooner; Architect's effort estimate should be the
actual tiebreaker here, not my guess.

---

**Q4 — Is candidate 2.5 (adversarial-discussion / Party-mode-inspired pattern)
worth building as a general tool, or does the existing ad hoc blameless-
retrospective pattern (used once, for the plugin-conversion pilot) already cover
this repo's actual need?**

This is the one candidate where I have real uncertainty about whether there's
enough recurring demand to justify formalizing a pattern that's so far been used
exactly once, informally, and worked.

➡️ **Recommend: wait for a second organic need before building this as a named,
reusable pattern.** One successful ad hoc use isn't yet evidence of a recurring
gap — formalizing prematurely risks the same over-engineering v1 itself already
explicitly avoided for scenario-based routing ("modeling it now, before any real
usage data, risks over-engineering the first release," `MULTI-AGENT-WORKFLOW.md`
§2). If the next co-thinking session or retrospective independently reaches for
something like this again, that's the trigger to formalize it. Confidence: medium
— this is the softest recommendation in this report; a reasonable case exists for
building it now specifically *because* it's cheap (documentation, no new
infrastructure) and low-risk to have sitting unused if the second need doesn't
materialize.

---

**Q5 — Should the "built" vs. "done" vocabulary (candidate 2.6) be adopted
immediately as terminology in `MULTI-AGENT-WORKFLOW.md`/`ROLE-DESCRIPTIONS.md`,
independent of when issue #309 itself gets scoped?**

The vocabulary is cheap and arguably already implicit in this repo's own
Reviewer-vs-Ties-merge-confirmation split (Reviewer's approval is a
recommendation; Ties' merge confirmation is the actual "done"). Naming it
explicitly costs nothing and could be adopted now, separate from #309's larger
branch-tier scope.

➡️ **Recommend: adopt the vocabulary now** (small documentation addition,
independent of 2.3/2.4/anything requiring Architect sizing), and flag it for
reuse whenever #309 is actually scoped. Confidence: high — this is nearly a fact
rather than a judgment call; the only reason it's listed as an open question at
all is that touching `ROLE-DESCRIPTIONS.md`/`MULTI-AGENT-WORKFLOW.md` at all is,
per this repo's own workflow, still a decision that needs an issue and Ties'
go-ahead before the file changes, not something Product can just do unilaterally
in this co-thinking session.

---

## Summary for Architect handoff

Highest-value, lowest-conflict candidates to size first: **2.2** (deferred-finding
disposition — trivial, closes a real gap), **2.6** (built/done vocabulary —
trivial, feeds #309), **2.1** (A3 escape-hatch formalization — small, directly
requested by #307's own backlog). **2.3** (epic retrospective) is the biggest
single win against live evidence (#322) but needs real architectural sizing
before commitment. **2.4** and **2.5** are worth Architect's read but are more
speculative — recommend Architect flag anything in this report that looks
harder or easier to build than Product's effort-shape guess suggests, per this
session's own disagreement-flagging convention.
