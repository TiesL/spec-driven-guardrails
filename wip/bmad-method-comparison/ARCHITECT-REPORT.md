Model/effort: Claude Sonnet 5, medium reasoning effort, Architect role.

# Architect report — BMad Method comparison (issue #324)

Co-thinking session (Orchestrator + Product + Architect only, per
`wip/multi-agent-development/PRD-MULTI-AGENT-WIP.md` §3.5). This is Architect's
proposed output, informed by Product's report but not deferential to it — per
this session's own instruction, every point of agreement, extension, or
disagreement with `wip/bmad-method-comparison/PRODUCT-REPORT.md` ("Product")
is marked explicitly in §3, not folded silently into §1/§2. Nothing here is
promoted into `PRD.md`/`ARCHITECTURE.md`/`wip/multi-agent-development/` until
Ties explicitly accepts it.

---

## 1. Technical/structural comparison

### 1.1 Role model

BMad's `bmad-build` is a single **Module** with a wide **Interface**: one
agent session owns investigate → plan → implement → review-trigger → commit,
i.e. it presents (and must be trusted across) every question this repo splits
across five roles. Depth, in `codebase-design` terms, comes entirely from
independent **reviewer subagents** bolted on at one **Seam** — the review
point — with a fresh context each (Blind Hunter, Edge Cases Hunter,
Verification Gap Finder). Everywhere else in BMad's flow, one Module answers
every question.

This repo's `PRD-MULTI-AGENT-WIP.md` §4 decomposes along the axis that
matters for **Locality**: a defect belongs to exactly one role's judgment
(*is the requirement right* / *is the design right* / *does it work as
intended* / *is there evidence it happened*), so when something goes wrong
the fix is locatable to one role's artifact, not diffused across a single
agent's undifferentiated reasoning trace. That is a genuine architectural
choice, not just "more agents": it trades BMad's cheap coordination (one
agent, no handoff cost) for cheaper fault localization (five narrow
Interfaces instead of one wide one). BMad recovers *some* of this Locality
only at the review Seam, by adding multiple reviewer Adapters after the fact;
this repo has it at every Seam, because every phase transition is a Seam
(artifact boundary), by construction.

The **two-adapters rule** is worth applying here directly: this repo's
Reviewer Interface already has two real adapters — the single-Reviewer-role
gate today, and (per Product's 2.4, discussed in §2 below) a
multi-lens-reviewer gate for higher-risk PRs. That's a real variation (risk
tier), so a seam for it is justified, not hypothetical. BMad's single-agent
build Interface, by contrast, has exactly one adapter in this repo's actual
usage pattern (Ties-in-the-loop, one work item at a time) — importing it
wholesale would mean building a seam for a variation this repo doesn't
currently have a second adapter for. This is the same conclusion Product's
§3.1 reaches by a different route ("this repo has already decided, with
evidence, that the unit of work should be smaller and more separated"); I
reach it via the deletion test: delete BMad's single-build-agent Module and
its complexity reappears entirely inside whichever role absorbs it, whereas
deleting one of this repo's five roles removes a *specific* question that no
longer gets asked — the complexity doesn't reappear, a check silently stops
happening. That is the structural argument for why this repo's decomposition
is deeper at the phase level than BMad's, not just differently organized.

### 1.2 Artifact/tracking conventions

`tickets.toml` (Initiatives → Epics → Entries, stable numeric ids per file)
is BMad's own durable-state Module, with its own Interface (the TOML schema)
and its own Adapter (whatever reads/writes it). This repo's tracking is not
a single Module in that sense — it's GitHub's own Issues/Epics/PR graph plus
`Covers:` tokens in `TEST-SCENARIOS.md`, verified by
`check-traceability.sh`. The deletion test cuts against adopting
`tickets.toml`: delete it from BMad and its complexity (ticket state, ids,
epic membership) reappears somewhere — it has to, tracking state doesn't
disappear — but in this repo that same complexity already lives in GitHub,
which is infrastructure this repo depends on for other reasons (PR review,
CI triggers, branch protection) and that a BA/PO/PM reader can already
navigate without extra tooling (README.md's UAT trace-back design goal).
Introducing `tickets.toml` alongside that would be a second, shallower
Module duplicating a Seam GitHub already owns — exactly the shallow-module
failure mode `codebase-design` warns against (large duplicated interface,
thin net-new behavior, since GitHub already has issue/epic/relation
semantics). I agree with Product's non-adoption (§3.4) and sharpen the
reasoning: this isn't only a stated anti-goal (README.md), it's a
depth argument — GitHub is already the deep module for this concern in this
repo's stack.

Where BMad's tracking model earns a genuine structural point this repo
lacks: **built vs. done as a named distinction on the same artifact.**
`tickets.toml`'s "a build finishes at built... the user or orchestrator
decides when to mark it done" is a two-state Interface on one Module (the
ticket). This repo currently expresses the same distinction implicitly and
diffusely — Reviewer's approval vs. Ties' merge confirmation on a
*work-item* PR, and (per issue #309) an unnamed, ad hoc equivalent one level
up, between a release branch's accumulated work-item merges and its own
promotion to `main`. That's not a tracking-file gap, it's a **vocabulary
gap at a real Seam this repo already has** (the release-branch → main
merge boundary). See §2.1 below for the effort read.

### 1.3 Autonomous-run guardrails

This is the comparison worth being most precise about, because BMad's
`bmad-build-auto` and this repo's #309 release-branch standing authorization
look superficially similar (both let an agent proceed through several PRs
without a human confirming each one) but solve different trust problems with
different shapes of guardrail.

**`bmad-build-auto`'s guardrail shape**: narrow scope, wide-open number of
invocations. One self-contained cycle per *ticket* (clarify → plan →
implement → review → terminal status), strictly single-ticket — "never
picks the next ticket itself... does not repeat across a backlog, coordinate
epics, or run a retrospective." The orchestrator names which tickets run,
explicitly, each time. Trust is bounded by *never letting the loop decide
what to work on next* — the human (or orchestrator) re-authorizes scope
every single invocation, but within one invocation the agent has full
run-to-completion autonomy short of marking done.

**#309's guardrail shape (as currently practiced, ad hoc)**: wide scope,
narrow number of invocations. One standing authorization, granted once per
release branch, covers an unbounded number of subsequent work-item PRs
merging into that branch — "work-item PRs targeting the release branch merge
on the executing session's judgment once the workflow... is satisfied."
Trust is bounded differently: not by re-scoping each time, but by the target
itself being non-final (a release branch, not `main`) and by every
underlying gate (five-role pipeline or an A3-authorized narrowing, CI,
`pre-merge-review`) still running unabbreviated per PR. The final promotion
(release → `main`) is where explicit re-confirmation re-enters, structurally
equivalent to BMad's real gate being "never marks a ticket done," not "never
merges a PR into the release/dev branch."

**Where they actually converge**: neither system lets the autonomous
mechanism touch the outermost promotion. BMad: "Build Auto never moves a
ticket to done." This repo: "the release branch's own merge into `main`
always needs Ties' explicit confirmation" (#309). Both put the irrevocable
step behind an unconditional human gate and grant autonomy only on the
reversible side of it. That's the load-bearing structural similarity, and
it's worth stating as a **shared invariant**, not a coincidence: an
autonomous-run mechanism is trustworthy exactly to the degree its scope ends
before the step that can't be undone.

**Where #309 is currently weaker than `bmad-build-auto`, structurally, not
just "undocumented":** BMad's guardrail is *self-limiting by construction*
— a single invocation cannot silently balloon into unattended backlog
processing, because the orchestrator must explicitly name each ticket, every
time. #309's ad hoc standing authorization has no equivalent
self-limiting property once granted: nothing in the mechanism as practiced
distinguishes "this release branch is scoped to four known work items" from
"this authorization now silently covers however many work items eventually
get routed at this branch." Issue #309 itself half-notices this ("Decide
whether a release branch is always tied to an epic, or can exist
independently") but doesn't name the guardrail gap directly. This is a real
structural finding, not present in Product's report — see §2.2.

### 1.4 Review/retrospective mechanics

BMad's finding-severity taxonomy (Patch / Defer / Decision needed) is a
three-way **Interface contract** for what a reviewer Adapter may return —
narrow, unambiguous, and machine-actionable (Patch = auto-apply). This
repo's Reviewer/QA finding format (summary, failure scenario, location,
category, CONFIRMED/PLAUSIBLE) is a different Interface, oriented around
*evidentiary weight* (is this reproduced or suspected) rather than
*disposition* (what happens to it next). The two are complementary, not
competing: CONFIRMED/PLAUSIBLE answers "how sure are we," BMad's taxonomy
answers "what do we do about it." Product's 2.2 candidate (deferred-finding
disposition) is exactly filling this gap, and I agree it's small — it's
adding one more field to an already-decided struct, not a new mechanism
(§3 below, no deviation).

The sharper structural point is `bmad-retrospective` vs. issue #322. BMad's
retrospective is a **Module with real depth**: it reads an epic's entire
diff/commits/plans as one unit and produces a bounded three-way verdict
(accepted / accepted-with-open-items / rejected), including checking whether
a *prior* epic's action items were actually implemented — i.e. it has state
that spans epics, not just one. #322 is the same *kind* of read (aggregate
defects across W1-W4's individual PRs — #320, #319, #318, #317 — collapsed
into one entry point before the release→main merge) but produced entirely
by hand, once, as a bespoke GitHub issue rather than a reusable Module. The
deletion test says this plainly: delete `bmad-retrospective` from BMad and a
gap reappears every time an epic closes, predictably, at the same Seam
(epic-completion), because that's the invariant it guards. Delete #322 and
the same gap reappears the next time an epic accumulates cross-work-item
defects — which is not hypothetical, it already happened once. That's the
two-adapters rule satisfied in reverse: one occurrence (#322) is a
hypothetical seam by BMad's evidence, but this repo already has a second,
independent data point that the underlying problem recurs — #307's own
"pipeline round-trip/ceremony cost" backlog entry documents the *same root
cause* (findings not aggregated until forced to be) showing up as scattered
per-PR overhead across #296/#299/#302, not only as #322's release-blocking
pile-up. Two real occurrences of the same underlying gap, in different
guises, is enough to justify a real seam, not a one-off fix. I agree with
Product's 2.3 and consider it the highest-leverage candidate in this report
(§2 below).

---

## 2. Architecture-level candidates, with effort estimates

Estimates below are my own technical read against this repo's actual
mechanisms (skill files, GitHub Actions, `check-traceability.sh`,
`compliance-evidence.sh`), not a restatement of Product's effort-shape
guesses. Where I land on the same shape as Product I say so in §3 rather
than repeating the estimate twice.

### 2.1 "Built" vs. "done" vocabulary, applied at the release-branch Seam (trivial)

**What, technically:** name the release-branch → `main` promotion as the
same built/done split BMad already names at the ticket level, and use it to
precisely state #309's confirmation-authorization rule: a work-item PR
merging into a release branch reaches **built** (Reviewer + CI + the
five-role pipeline or an authorized A3 narrowing all satisfied); the release
branch's own merge into `main` is the **done** decision, exclusively Ties'.
This is documentation only — no new Module, no new Interface, no new Seam.
It makes explicit a distinction that already exists mechanically (per §1.2)
but is currently unnamed.

**Effort: trivial.** A paragraph in `CLAUDE.md`'s Branch strategy section
(or wherever #309 eventually lands) plus a cross-reference from
`ROLE-DESCRIPTIONS.md`. No code, no skill logic, no CI change. Agrees with
Product's 2.6 effort-shape ("small"); I'd go one notch lower (trivial, not
small) because there is genuinely nothing to design — the Seam already
exists, this only names it.

### 2.2 Self-limiting scope for release-branch standing authorization (small-medium)

**What, technically:** close the structural gap identified in §1.3 — #309's
ad hoc standing authorization currently has no mechanism that bounds *how
many* work items it silently covers once granted. Two candidate shapes,
Architect's call between them deferred to whoever actually scopes #309, but
both are cheap:

- **(a) Enumerated scope, BMad-style.** A release branch's authorization
  names its covered work items explicitly at creation time (mirrors
  `bmad-build-auto`'s "orchestrator explicitly names which tickets run" —
  the *shape* of the guardrail, not the mechanism, since this repo has no
  ticket-loop to invoke). A work-item PR targeting the release branch but
  not in the named set requires a fresh authorization, loudly, the same way
  A3's escape hatch already requires a loud, per-instance record.
- **(b) Time/count-boxed re-confirmation.** The standing authorization
  expires after N work items or M days, whichever first, requiring a
  lightweight re-confirmation from Ties to continue — cheaper to implement
  (a counter, not a named list) but less precise than (a).

**Why it's a real seam, not speculative:** the deletion test applies in the
scary direction here — if this guardrail is never added, nothing currently
stops a release branch's standing authorization from silently accreting
scope indefinitely as more work items get routed at it, which is exactly the
kind of drift A3's "loud, logged, per-instance" design was built to prevent
at the role-narrowing layer. This is the same invariant (A2/A3's family: no
silent scope expansion of an autonomy grant) applied one level up, at the
branch-authorization layer, where it currently isn't applied at all.

**Effort: small-medium.** (a) is a documentation + discipline change (name
the scope at branch-creation time, check it before each merge) — small. (b)
needs a place to record/check a counter, which this repo doesn't currently
have anywhere near git branches — likely a comment convention on the
tracking epic issue, reusing the OQ9 compliance-comment pattern rather than
new tooling. Either way, this is squarely #309's own scope, not a new issue
— flagging it here so #309's eventual write-up doesn't miss it, since
neither Product's report nor #309's current text names this specific gap.
**This is new scope Product's report did not surface** (§3.6).

### 2.3 Epic-closing retrospective gate (medium-large — larger than Product's estimate)

**What, technically:** agree with Product's 2.3 in shape (a gate that reads
an epic's aggregate diff/commits/plans/PRs as one unit, producing
accepted/accepted-with-open-items/rejected, unfinished work items defaulting
to rejected unless Ties overrides). Sizing the actual Module:

- **Interface:** minimal — takes an epic issue number, reads its linked
  work-item PRs and their `pre-merge-review` markers, `compliance-evidence.sh`
  output where available, and `TEST-SCENARIOS.md` deltas across the epic's
  branch history. Output: one issue comment, same shape as the existing OQ9
  compliance-comment pattern (§6's worked example against #265/#279) —
  reusing that pattern directly is correct and keeps this from becoming a
  new artifact type.
- **Implementation depth is where this is bigger than "medium":** unlike
  the OQ9 compliance comment (which reads *one* PR's already-posted
  evidence and restates it), a real retrospective has to *aggregate across
  N PRs* and detect cross-PR patterns — Product's own example (#319's
  mawk-regex bug affecting both `compliance-evidence.sh` and
  `role-label-staleness.sh`) is exactly a pattern that's invisible from any
  single PR's diff and only shows up when two PRs' file-touch sets are
  compared. That's non-trivial: it needs either (i) a role/agent capable of
  reading and correlating multiple PRs' full diffs in one session (context
  budget scales with epic size, not PR size — a real cost this repo hasn't
  had to pay anywhere else in the pipeline), or (ii) a narrower, cheaper
  mechanical pre-pass (e.g. flag any file touched by ≥2 of the epic's PRs
  for the retrospective role to look at specifically) that keeps the
  expensive full-read step bounded.
- **Who runs it** (Product left this an open question, 2.3's effort-shape
  section): my read is a **sixth, distinct invocation**, not "Reviewer
  extended." Reviewer's existing Interface is scoped to one PR's evidence
  chain; stretching it to also own cross-epic aggregation gives it two
  different Depths at once (per-PR verification vs. cross-PR pattern
  detection) behind one Interface — exactly the shallow-module failure mode
  this project's own `codebase-design` skill warns against when an
  interface accretes unrelated responsibilities. A new, narrow
  `role:retrospective` invocation, dispatched once per epic close, fresh
  context (same fresh-dispatch precedent as every other role per Decision
  3), keeps Reviewer's own Interface undisturbed.

**Effort: medium-large.** Larger than Product's "medium" because the
aggregation-across-PRs step is genuinely new capability this repo's
pipeline doesn't currently exercise anywhere (every other gate, including
`pre-merge-review`, operates at single-PR scope) — this is not a text
clarification or a new field on an existing struct, it's a new Module with
a nontrivial Interface (what counts as "the epic's evidence," bounded
enough to fit a session's context). Sizing more precisely needs a decision
on (i) vs. (ii) above before real estimation — flagging that as the next
open question for whoever picks this up, not resolving it here.
**Deviation from Product's effort-shape — see §3.3.**

### 2.4 Named review-depth tiers (small — matches Product, mechanism specified further)

**What, technically:** agree with Product's 2.4 in shape. The concrete
Module: a size/risk classifier (files touched, whether the PR touches any
of Reviewer's existing risk-trigger categories — auth, secrets, deploy/CI,
IaC, sensitive data, untrusted input, already enumerated in
`PRD-MULTI-AGENT-WIP.md` §4's security table) decides "quick" (today's
single-Reviewer gate, unchanged) vs. "thorough" (Reviewer plus N independent
lens-Adapters, each producing a finding set in the already-decided minimal
format, before Reviewer's own final gate). The lens-Adapters are not new
roles (agree with Product's non-adoption §3.2) — they're additional,
disposable Adapters at the same Reviewer Seam, torn down after one use, same
as every other role's fresh-dispatch pattern.

**Effort: small.** `pre-merge-review`'s `context: fork` and finding-format
conventions already exist; the *only* new pieces are (a) the classifier
(reusable directly from Reviewer's existing security-trigger list — no new
taxonomy needed, contra even inventing one) and (b) dispatching more than
one fresh sub-agent instead of one. This is a shallow addition to an
already-deep Reviewer Seam, not new infrastructure. I'd note, contra
Product's Q3 recommendation to defer this into v2/#307: the *mechanism*
itself is cheap enough that bundling it with #307's ceremony-cost concerns
conflates a small implementation cost with a real usage-cost question
(dispatching 2-3 reviewer instances on every "thorough" PR *does* add
ceremony) — those are separable, see §3.4.

### 2.5 A3 escape-hatch formalization (small — matches Product)

Agree with Product's 2.1 in shape and effort. One clarification worth
adding: the formalized decision procedure should explicitly require
**one role narrowed per invocation**, not stated as a soft preference but as
the actual rule — A3's own pilot-finding paragraph already names the cost of
not doing this ("narrowing three roles at once... attribution of which skip
caused which defect was muddled"). If 2.1 is built without hard-coding this
constraint, the same attribution failure will recur the very next time
someone reaches for convenience over discipline under deadline pressure.
This is a small addition to Product's candidate, not a deviation in kind —
noted here rather than in §3 since it sharpens rather than contests
Product's framing.

### 2.6 Deferred-finding disposition field (trivial — matches Product)

Agree fully with Product's 2.2, no technical deviation. This is a one-field
addition to an already-decided struct (`ROLE-DESCRIPTIONS.md`'s finding
format); there is no architecture decision here beyond naming the field.

---

## 3. Deviations from Product's report

Per this session's instruction, every point of agreement-and-extension,
disagreement, or added scope is marked here explicitly, quoting Product's
specific claim.

### 3.1 Agreement, extended: single-agent-build non-adoption (§3.1 of this report)

Product's §3.1: *"Collapsing v1 back toward a single build agent would undo
the entire premise of epic #65... a rejection of importing its unit of work
when this repo has already decided, with evidence, that the unit of work
should be smaller and more separated."*

**Agree, and extend with a structural argument Product's report doesn't
make**: I add the deletion-test framing above (§1.1) — deleting one of this
repo's five roles removes a specific question that stops being asked;
deleting BMad's single build agent just relocates the same complexity
elsewhere inside whatever absorbs it. That's a sharper, vocabulary-grounded
version of the same conclusion, not a different one.

### 3.2 Agreement, extended: `tickets.toml` non-adoption (§3.4 of Product's report)

Product's §3.4: *"Introducing a parallel `tickets.toml`-style file would
duplicate what GitHub Issues + `Covers:` tokens already do... The vocabulary
(2.6, built vs. done) is worth borrowing; the file format is not."*

**Agree with the conclusion, extend the reasoning**: Product grounds the
non-adoption in README.md's stated anti-goal. I add the depth argument
(§1.2 above) — GitHub is already the deep Module for this concern in this
repo's stack; `tickets.toml` would be a second, shallow Module duplicating
that Seam. Same verdict, sharper justification using this role's required
vocabulary.

### 3.3 Disagreement: epic-retrospective effort estimate

Product's §2.3 effort-shape: *"Effort shape: Medium — needs a new
role-dispatch shape... plus deciding where its output lives... Not small
because it's a new gate in the pipeline, not a text clarification."*

**Disagree with the sizing, not the shape.** Product correctly identifies
this as a new gate, not a text change, but underweights the actual new
capability required: cross-PR pattern detection across an epic's full diff
history is something no existing mechanism in this repo does today (every
other gate, `pre-merge-review` included, operates at single-PR scope). I
size this medium-large, not medium, specifically because of the
context-budget and correlation-mechanism question raised in §2.3 above,
which needs its own design decision (a full-read role vs. a mechanical
file-overlap pre-pass) before real estimation is possible. This is the kind
of "flag anything that looks harder... than Product's effort-shape guess
suggests" Product's own handoff section explicitly invited.

### 3.4 Disagreement: where review-depth tiers (2.4) should be scoped

Product's Q3: *"Recommend: v2 (#307), specifically because 'dispatching more
than one reviewer instance' has real ceremony-cost implications that #307's
own... NFR item is already tracking — bundling this with that existing
cost-awareness thread avoids introducing a new source of the same problem
#307 already flags, unexamined."*

**Partial disagreement.** I agree the *ongoing usage cost* (ceremony from
dispatching multiple reviewer instances per "thorough" PR) belongs in #307's
cost-awareness thread — that part of Product's reasoning is sound. But
Product's recommendation conflates that usage-cost question with the
*implementation* cost, which I size as small and structurally
low-risk (§2.4 above: reuses `pre-merge-review`'s existing fork/fresh-context
pattern and Reviewer's existing risk-trigger list almost unchanged). Building
the classifier+dispatch mechanism now, but gating its *default-on for
"thorough"* usage behind #307's NFR discussion, gets both: the cheap,
low-risk piece ships without waiting on an epic that isn't scoped yet, and
the genuine ceremony-cost question still gets weighed in #307 before this
becomes a routine, always-invoked behavior. Recommend splitting Product's
single question into two: (a) build the mechanism now (small, low risk) vs.
(b) when does "thorough" become the default trigger for a given PR shape
(genuinely #307's call). Product's report treats these as one question;
they're separable.

### 3.5 Agreement, extended: autonomous-loop non-adoption (§3.3 of Product's report)

Product's §3.3: *"v1's actual usage so far... is Ties-in-the-loop the entire
way, on one work item at a time, and `WORKFLOW.md` step 4... plus
`MULTI-AGENT-WORKFLOW.md`'s 'merge/release stays human-only, permanently'...
already forecloses the part of autonomy BMad's loop is built to enable."*

**Agree with the non-adoption conclusion. Extend with a distinct structural
finding Product's report doesn't reach**: the comparison in §1.3 above shows
`bmad-build-auto` and #309's release-branch authorization aren't actually
solving the same problem in the same shape — they're two different answers
to "how much autonomy before the irrevocable step," and #309's answer
currently has a real self-limiting-scope gap `bmad-build-auto`'s design
doesn't have (§1.3, §2.2). Product's report treats #309 only as "BMad's
epic tier maps loosely" (§1.6) and doesn't examine #309's own guardrail
shape against `bmad-build-auto`'s guardrail shape directly — that
comparison is what surfaces 2.2 as a candidate, which is new scope, not
present anywhere in Product's report.

### 3.6 Added scope: self-limiting authorization for release branches (2.2)

Not addressed in Product's report at all. Product's §1.6 notes #309 as an
"informal... release-branch tier" gap adjacent to BMad's ticket hierarchy,
but frames it purely as a vocabulary/tiering gap (resolved by borrowing
built/done language, Product's 2.6). My read of #309 against
`bmad-build-auto`'s actual guardrail *mechanism* (not just its vocabulary)
surfaces a distinct, more concrete gap: the standing authorization itself
has no scope-limiting property once granted (§1.3, §2.2 above). This is
Architect's own technical read surfacing something Product's report doesn't
cover, flagged per this session's brief ("any of your own the technical
read surfaces that Product didn't").

### 3.7 No deviation, confirming: adversarial-discussion / Party-mode candidate (2.5)

Product's Q4 recommends waiting for a second organic need before
formalizing this. I have nothing to add or contest technically — this
candidate has no architecture-level shape to size yet (it's a facilitation
pattern, not a Module/Interface/Seam question), so Architect's role has
little to say beyond agreeing the wait-for-a-second-instance heuristic is
sound. Noted for completeness, not a substantive deviation.

---

## 4. Recorded technical decisions/recommendations

### Resolvable as an architecture judgment call now (no Ties input needed)

- **2.3's execution model: a sixth, distinct `role:retrospective` invocation,
  not an extension of Reviewer's existing Interface.** This is a pure
  depth/Interface-cleanliness argument (§2.3) — stretching Reviewer to cover
  both per-PR verification and cross-epic pattern detection creates a
  two-Depth Interface, which this repo's own `codebase-design` vocabulary
  already gives grounds to reject. Recording this as settled unless Ties
  has a reason (e.g. operational cost of a sixth role-dispatch shape) I'm
  not weighing.
- **2.4's mechanism reuses `pre-merge-review`'s existing `context: fork` and
  Reviewer's existing risk-trigger list, with no new risk taxonomy.** Same
  reasoning as OQ5's already-settled "no new taxonomy, reuse the OWASP-style
  categories already in place" precedent (`ARCHITECTURE-MULTI-AGENT-WIP.md`,
  "Still open after this document," OQ5) — this is just that same precedent
  applied to a new gate, not a fresh decision.
- **2.5's "exactly one role narrowed per A3 invocation" as a hard
  requirement, not a soft preference**, when 2.1 (Product's escape-hatch
  formalization) is written up. Directly evidenced by A3's own pilot-finding
  paragraph; not a judgment call, a lesson already paid for once.

### Still needs Ties

- **§2.2 (self-limiting release-branch authorization): choice between
  enumerated-scope (a) and time/count-boxed (b).** This is a genuine
  tradeoff between precision and implementation cost that depends on how
  Ties actually expects to use release branches going forward (one epic at
  a time, predictably, vs. more fluid cross-epic batching) — a preference
  this report can't discover from evidence alone (A10).
- **§2.3's aggregation-mechanism choice (full cross-PR read vs. a mechanical
  file-overlap pre-pass feeding a narrower read).** Real cost/precision
  tradeoff; needs sizing against actual epic sizes this repo expects to
  produce, which is a product-scale judgment, not something inferable from
  this session's evidence.
- **Whether §2.2 becomes its own issue or folds into #309's existing
  scope.** Mechanically it's #309's problem (same Seam), but Ties may want
  it split out given #309 is already fairly large in stated scope.
- **§3.4's split recommendation (build 2.4's mechanism now, defer only its
  default-on trigger policy to #307)** — this is a scoping call Product and
  Ties should weigh together, since it revises Product's Q3 recommendation
  rather than just sizing it.
- Everything Product's own §4 already listed as open (Q1, Q2, Q5) — this
  report doesn't re-litigate those; §2's effort estimates are additional
  input for Ties' and Product's prioritization decision, not a resolution
  of Product's open questions themselves.
