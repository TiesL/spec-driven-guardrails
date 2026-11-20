Model/effort: Claude Opus, high reasoning effort, Product role.

# Product report — "Implement the multi-agent workflow" as a scoped epic

> **Status: proposed, not final.** This is a Product-role artifact from a pre-decision
> co-thinking step (`PRD-MULTI-AGENT-WIP.md` §3.5, Decision 5, A6), written into
> `wip/multi-agent-rollout/` rather than into any accepted document. Everything here that
> reads differently than epic #65 or `PRD-MULTI-AGENT-WIP.md` currently frames it is marked
> **[DEVIATION]** with the reasoning. Nothing below closes an open question — §6 batches the
> decisions that are Ties' to make.
>
> Scoped input treated as a **floor** (A8): named inputs were epic #65 and issues #237/#293/
> #294, `wip/multi-agent-development/*`, and `vendor/grilling/SKILL.md`. Beyond that set I
> read, to answer questions the named files could not settle: `gh label list` and
> `gh issue list` (live GitHub state), `skills/` (which skills actually exist),
> `check-no-dutch.sh`, `adopt.sh`'s `install_skills()`, `CHANGES.md`, and a repo-wide grep
> for `role:<name>` label usage. Each is cited where it is used. Per A10, every one of those
> is a *fact* I looked up rather than a question for Ties.
>
> Effort estimation is deliberately absent — that is Architect/QA/Fullstack Developer/
> Reviewer's own contribution to prioritization, never Product's (role contract, §Product).

---

## 1. Problem and desired outcome

### The situation, stated as facts

Epic #65's design phase is complete and the direction is accepted (2026-09-21,
`DIRECTION-CHECK-SUMMARY.md`). What exists is a fully-decided specification across three
documents plus role contracts. What does **not** exist is any way to run it that does not
depend on a human or orchestrator re-deriving the role contracts by hand from a `wip/`
document each time. Concretely, verified against the repo and live GitHub state:

| Decided in the design | Actual state in the repo | Source |
|---|---|---|
| "The new role/orchestration layer gets its own skill, not a replacement of existing ones" (PRD §9 OQ10) | No such skill. `skills/` holds 12 skills; none is multi-agent/role-related. The role contracts live only in `wip/multi-agent-development/ROLE-DESCRIPTIONS.md`. | `ls skills/*/` |
| Reviewer's security trigger list is embedded "in the skill that records Reviewer's role contract (**still to be written**)" (PRD §4, Security) | That skill does not exist; the trigger list lives in prose in two WIP documents. | PRD §4; `ls skills/` |
| A4: each role session gets a **skill-based file/directory scope contract** stating which paths it may read/write | No per-role path scope is written down anywhere — not in `ROLE-DESCRIPTIONS.md`, not in a skill. A8 requires every dispatch prompt to declare floor-or-ceiling, but there is no default source for a role to inherit. | `ROLE-DESCRIPTIONS.md`; grep |
| A5: a `role:<name>` label tracks the currently active phase | The five labels do not exist on the repo, and no script, hook, doc or template outside `wip/multi-agent-development/` mentions them. | `gh label list` (10 labels, none `role:*`); repo-wide grep: zero hits |
| OQ9: compliance is reported as one orchestrator issue comment per work item, rows pointing at existing evidence | Never posted once. The "worked example" is a table *inside* `PRD-MULTI-AGENT-WIP.md` describing a work item (#265/PR #279) that had already merged — retrospective prose, not an artifact that exists on an issue. | PRD §6; issue #265 has no such comment |
| The role contracts' source of truth is PRD §4 | PRD §4 is Dutch; `ROLE-DESCRIPTIONS.md` states that on a discrepancy the reader must "re-read the Dutch source directly" rather than trust the English file. #237 is open. | `ROLE-DESCRIPTIONS.md` lines 10-15; issue #237 |

So the gap between "designed" and "operational" is not a missing decision. Every design
question except OQ11 is closed. The gap is that **none of the decided mechanisms has been
instantiated as a durable thing in the repo, and no work item has ever produced the evidence
the design says a work item produces.**

### Problem statement

Epic #65's design is accepted but inert. Running the five-role pipeline today requires an
orchestrator to hand-assemble each role's contract, scope and dispatch prompt from a WIP
document, and to hand-write the compliance evidence afterwards — so every run is bespoke,
its fidelity depends on that run's orchestrator remembering the design, and nothing
mechanical catches a role that was skipped, mis-scoped, or never evidenced. That is the same
failure mode the epic exists to prevent (PRD §2: "the agreed workflow only partially
followed"; "decisions captured only in chat hand-offs"), relocated from the roles to the
orchestration around them.

### Desired outcome (Jobs-to-be-done)

Per §3.4's own rule — this repo's audience is the maintainer/developer and the workflow
itself, not an external end-user persona, so JTBD rather than a user story:

> **When** a real change needs building in this repo and I want the five-role pipeline to run
> it, **I want** the role contracts, scopes, phase labels and compliance evidence to be
> instantiated things I can invoke and inspect, **so that** each run is reproducible by any
> fresh session, and non-compliance is visible in an artifact instead of depending on whoever
> ran it that day.

Measurable form of "done" for the epic (not for the first work item):

1. One real work item has gone through all five roles and produced, on GitHub, the artifacts
   the design predicts: per-phase `role:<name>` label transitions, per-stage model/effort
   records, a `pre-merge-review` marker, green CI, a PR↔issue link, and one compliance
   comment — none of it hand-waved.
2. A fresh session with no memory of this work can run the pipeline again from repo contents
   alone.
3. OQ11 (target release) is answerable, because the evidence Ties needs to judge it exists.

---

## 2. Business case — why this, why now

**Why this scope rather than "implement the orchestrator".** PRD §6 settles that context is
artifact-based with no separate state object, and `ARCHITECTURE-MULTI-AGENT-WIP.md`
"Dependencies" says explicitly: *"None new. Uses only what this project already has."* So
there is no orchestrator system to build. The only thing "implementing the multi-agent
workflow" can honestly mean is: turn the decided *contracts and records* into repo artifacts,
and prove the loop closes on a real change. Anything larger would be inventing software the
design deliberately rejected.

**Why now, three reasons, in order of force.**

1. **OQ11 is the last thing blocking epic #65, and only a real run resolves it.** Issue #294
   and PRD §9 OQ11 both say so in as many words. Every further design refinement is
   speculation until the process has run once.
2. **The design's own perishability.** The specification is large (≈1,900 lines across four
   documents), decided at a single point in time, and has never been tested against
   execution. The co-thinking pilot — which exercised only Product+Architect — found four
   real process defects in one run (`CO-THINKING-PILOT-RETRO-ORCHESTRATOR.md` §2), three of
   which became architecture requirements A7/A8/A9. Extrapolating: the untested three-fifths
   of the pipeline (QA, Fullstack Developer, Reviewer) almost certainly contains comparable
   defects, and they get cheaper to find the sooner the pipeline runs. Every week the design
   sits unexecuted, the cost of the corrections it will need goes up, because more design has
   been layered on top of untested assumptions.
3. **The repo is about to be reshaped by epic #282 (plugin conversion).** Role contracts,
   file scopes and labels are exactly the kind of thing that acquires a second home if it is
   defined after the plugin split rather than before. Defining them now, in one place, while
   the plugin work is still pre-implementation, is materially cheaper than reconciling two
   copies later.

**What it costs if we do nothing.** The specification stays a document; the repo keeps
working single-agent; OQ11 stays open indefinitely; and #65 becomes the thing the workflow
warns about — a spec with no mechanism (`PRD.md`'s own "From prose to mechanism" thesis,
epic #11). That is a self-inflicted counterexample in a repo whose entire value proposition
is that agreements must be mechanized to survive.

---

## 3. Proposed epic framing

**Proposed epic title:** *Make the multi-agent workflow executable (roles, scopes, evidence)*

**[DEVIATION — epic structure]** Epic #65 currently carries this work as two of its own
unchecked work items (#237, #294) and says its "design follow-up items are deliberately
still empty — only drafted once the open questions below are decided." Every open question
except OQ11 *is* now decided, so that condition is met and follow-up items are now
legitimate. My recommendation is nonetheless to open a **separate epic** for the rollout and
leave #65 as the design record, because the two have different definitions of done: #65 is
done when the direction is accepted and OQ11 is answered; the rollout epic is done when the
mechanisms exist and a change has flowed through them. Merging them would make #65
open-ended. This is a structural preference, so it is Q1 in §6, not a decision I take here.

**Epic scope (proposed), in dependency order:**

| # | Slice | Why it is in the epic |
|---|---|---|
| **W1** | **Compliance evidence collection for one work item** — the first work item, fully specified in §4 below. | The one decided mechanism (OQ9) that has never produced a real artifact, and the one the pilot itself must emit. |
| W2 | Role-contract skill: promote `ROLE-DESCRIPTIONS.md` into `skills/`, adding the per-role file/directory scope contract A4 requires, the floor/ceiling default A8 requires, and Reviewer's security trigger list PRD §4 says belongs there. | Closes the largest designed-but-absent mechanism; makes dispatch reproducible. Depends on #237 (see §6 Q7). |
| W3 | Create and wire the five `role:<name>` labels (A5), including how staleness is caught. | Small, but A5's "violated if left stale" needs somewhere to live; most natural alongside W2. |
| W4 | Run a real, non-meta work item end-to-end through all five roles and post its compliance comment (this is #294's substance, executed with W1-W3 in place). | Resolves OQ11. |

W2-W4 are sketched, not specified. Per the role contract, Product does not estimate their
effort; Architect/QA/Fullstack Developer/Reviewer supply that when each is scoped.

---

## 4. First work item — full specification

### W1 — Collect a work item's compliance evidence into the decided report shape

**Recommended as the first work item.** Rationale against the alternatives is in §5.

#### Jobs-to-be-done

> When a work item has merged and I need to show the workflow was actually followed, I want
> its compliance evidence assembled from the artifacts that already exist, in the row-per-gate
> shape OQ9 decided, so that I can post one comment on the issue without hand-collecting six
> different links and without inventing a second source of truth.

#### Description

OQ9 is decided and closed: compliance reporting reuses `WORKFLOW-ADOPTION.md`'s
row-per-decision shape (Change/Answer/Date/Notes → Gate/Status/Evidence), scoped per work
item, posted as **one orchestrator issue comment after merge**, with every row pointing at
evidence that already exists. This work item **implements that decision; it does not reopen
it.** The report shape, the gate list and the posting moment are inputs from the design, not
choices to be re-made.

What it builds: a read-only collector that, given a work item's issue number, gathers the
already-existing evidence for each decided gate and renders the OQ9 table to stdout. It does
not post, does not judge, does not decide, and holds no state — the same category as
`check-traceability.sh`, `check-pr-issue-link.sh` and `wait-for-ci.sh`, which are this repo's
established idiom for "mechanical, structural, no judgment."

**[DEVIATION — "no new mechanism"]** PRD §6 says of OQ9, in Dutch, that it needs no new
report format and no separate dashboard (rendered in English here; the Dutch source is still
untranslated, see #237). A collector is neither a new format (it emits exactly the decided one) nor
a dashboard (it emits text, to stdout, on demand). But it *is* new code in a design whose
Dependencies section says "none new," and the orchestrator is decided to be a responsibility
rather than a component. I judge the collector to be on the safe side of that line for the
reason above, but the line is Ties' to draw — Q3 in §6, with a no-code fallback stated there.

#### Scoped requirements

- **R1 — Gate rows come from the decided list.** The gates are those in PRD §6's worked
  example: per-stage model/effort records; review model adequacy or an explicit exception;
  quality review before merge with findings in the PR; CI green; traceability link 3 (PR↔
  issue); Ties' explicit merge confirmation. No gate is added or dropped by this work item.
- **R2 — Every row cites pre-existing evidence.** Each row's Evidence cell names a thing that
  exists independently of the collector (a marker comment, a check run, a PR field). The
  collector never asserts a gate passed on its own authority.
- **R3 — Unknowable is not the same as failed.** A gate whose evidence cannot be established
  from artifacts — Ties' merge confirmation is the standing example, since it happens in
  conversation — is rendered as explicitly unverifiable-from-artifacts, not as a pass and not
  as a failure. Silently rendering it green would make the report a rubber stamp; rendering
  it red would make every report red.
- **R4 — Read-only.** No posting, no labels, no writes to GitHub, no merge. A2/A11 make the
  destructive side human-only; this stays on the safe side by having no write path at all.
- **R5 — Deterministic and offline-testable.** Its GitHub access sits behind a seam so the
  tests run without network and without a live issue. (Seam placement itself is QA's and
  Architect's call, per `tdd-seams` and the role split — R5 states the requirement, not the
  design.)
- **R6 — Follows this repo's own conventions.** Named and wired per `check-convention`;
  Bash-3.2-compatible like the repo's existing scripts; a `TEST-SCENARIOS.md` entry with a
  `Covers:` token per `write-spec`.

#### Acceptance criteria

**AC1 — The decided report shape is produced for a real, already-merged work item**
- **Given** issue #265 / PR #279, an already-merged work item whose evidence exists on GitHub
  today, and which PRD §6 already uses as its worked example
- **When** the collector is run against it
- **Then** it emits the Gate/Status/Evidence table with a row per R1 gate, and each row's
  evidence matches what PRD §6's hand-written example recorded for that same work item —
  confirming the collector reproduces the decided example rather than a new interpretation of
  it

**AC2 — Evidence is cited, never asserted**
- **Given** any gate row the collector emits
- **When** its Evidence cell is read
- **Then** it names a specific artifact (marker comment, check run, PR field) that a reader
  can open independently, and no row claims a status without one

**AC3 — A missing gate renders as missing**
- **Given** a work item whose evidence for one gate is absent (for example: a PR with no
  `pre-merge-review` marker, or no `Closes #N` in its body)
- **When** the collector runs
- **Then** that row renders as not-evidenced, the remaining rows still render, and the run
  does not abort — a partial report is the honest output, not an error

**AC4 — Human-only gates are neither faked nor failed**
- **Given** the merge-confirmation gate, which by A2 happens in conversation and leaves no
  artifact
- **When** the collector runs
- **Then** that row is rendered as unverifiable-from-artifacts with a stated reason, distinct
  in the output from both a pass and a fail

**AC5 — It is read-only**
- **Given** a run against any issue or PR
- **When** the run completes
- **Then** no GitHub object has been created, modified, labelled or merged — verifiable from
  the implementation containing no write call, and asserted by a test

**AC6 — Tests run offline and deterministically**
- **Given** the repo's own `check`
- **When** it runs in CI with no GitHub credentials
- **Then** the collector's tests pass, exercising AC1-AC4 against fixtures rather than live
  API calls

**AC7 — It is discoverable and wired like every other check in this repo**
- **Given** `check-convention` and `write-spec`
- **When** the work item is complete
- **Then** the script is reachable through the established entry point, its scenarios are in
  `TEST-SCENARIOS.md` with a resolving `Covers:` token, and `./check` passes

#### Why this is a good first five-role pilot

- **Product** has a genuinely contestable scope question (R3/AC4: what does a gate with no
  artifact render as?) — not a rubber-stamp phase.
- **Architect** has a real decomposition to make: the GitHub-access seam (R5), and whether
  this is one deep module or accretes shallow per-gate helpers — precisely what the vendored
  `codebase-design` deletion test and two-adapters rule exist for.
- **QA** has a real strategy choice: fixture-based unit tests versus one recorded end-to-end
  run, and how to test a read-only guarantee (AC5) without network.
- **Fullstack Developer** has actual red-before-green shell code, not prose.
- **Reviewer** has something to review that CI actually exercises, plus a semantic
  traceability judgment (does the emitted table really match the decided gates?).
- **It dogfoods immediately:** the pilot's own compliance comment is produced by the thing
  the pilot built. If the collector is wrong, the pilot's own evidence exposes it.

---

## 5. Alternatives weighed and rejected as the *first* item

| Candidate | Why not first |
|---|---|
| **#283 / epic #282's E1 (bootstrap admission manual)** — #294's current named candidate. | **[DEVIATION — this contradicts issue #294 as written.]** Two reasons. (a) *Wrong content for the roles that have never run:* #294 itself calls it "smallest, no code," but QA, Fullstack Developer and Reviewer are exactly the three untested roles, and all three are strongest on code with tests and CI signal. A prose deliverable under-exercises the untested part of the pipeline — the pilot would return a weak signal about the thing it exists to test. (b) *Wrong epic:* it belongs to #282 and inherits that epic's own open scope; a defect found during the pilot becomes ambiguous — pipeline problem or plugin-design problem? A pilot on this epic's own work keeps the variables separated. I recommend #294 be re-pointed at W1, not closed — its AC2 (resolve OQ11) stays exactly as written. |
| **W2, the role-contract skill, first.** | Tempting, since it is the biggest gap. But it is not a *blocker*: `ROLE-DESCRIPTIONS.md` states it is "meant to be quoted verbatim into a role's dispatch prompt," and this very session is evidence that dispatch works that way today. So W2 improves repeatability rather than unblocking the pilot, and it is docs-shaped — same under-exercising problem as #283. It also has a real dependency (#237, see Q7) that W1 does not. Better as the second slice, informed by what the first real run shows the contracts are actually missing. |
| **#237, translating `PRD-MULTI-AGENT-WIP.md`.** | Asked explicitly, so answered explicitly: **it is not "implementing the multi-agent workflow," but it is not purely orthogonal either.** It is housekeeping today, because nothing operational depends on that file. It becomes a *dependency* the moment W2 promotes the English `ROLE-DESCRIPTIONS.md` into a skill, because that file currently disclaims its own authority and points readers back to a Dutch source — shipping a normative skill that says "if in doubt, read the Dutch document instead" is not acceptable. One fact worth Ties knowing, found while checking this: `check-no-dutch.sh` lists `./wip/multi-agent-development/PRD-MULTI-AGENT-WIP.md` under its **permanent** exclusions, while that script's own header reserves permanent status for things that "never get translated, by design" and keeps issue-tracked ones in a separate *pending* list that tightens when the issue closes. With #237 open, the entry appears to be in the wrong list. That is a fact, not a decision, so it is stated here rather than asked — but whether to fix it inside #237 is Q7. |
| **A "run the pipeline" item with no deliverable of its own** (pure process rehearsal). | Rejected: PRD §3.3 makes completion an evidence-based decision. A rehearsal with no real deliverable produces no evidence worth judging, and would tell us nothing about whether the gates bite. |

---

## 6. Open questions for Ties — round 1

Per A10 and `vendor/grilling/SKILL.md`: these are **decisions**, batched as one frontier
round, each with my recommended answer. Facts I could look up are not here — they are in §1.
Questions whose prerequisites are these answers are deliberately held for round 2 (listed
after).

❓ **Q1 — Separate epic, or more work items on #65?**: Every open question on #65 except OQ11
is decided, so drafting follow-up items is now permitted by #65's own condition. The choice is
whether the rollout work hangs off #65 (keeping one epic, at the cost of #65 never closing
until the mechanisms ship) or becomes its own epic that references #65 as its design record
(two epics, each with a crisp definition of done).

➡️ **New epic**, *Make the multi-agent workflow executable*, referencing #65. Keep #65 as the
design/acceptance record; it closes when OQ11 is answered by the new epic's pilot run. #294
moves to the new epic (or stays on #65 and is referenced — either works, say which you
prefer).

---

❓ **Q2 — Is W1 (compliance evidence collection) the right first work item?**: §4 specifies
it; §5 argues it over #283, over the role-contract skill, and over #237. The competing view is
that the role-contract skill is the bigger gap and should come first.

➡️ **Yes, W1 first.** It is the only candidate that is simultaneously small, real code with
CI signal (exercising the three roles that have never run), a decided-but-never-instantiated
mechanism, and self-dogfooding — the pilot's own compliance comment comes out of it. The
role-contract skill follows as W2, better informed by what the first run exposes.

---

❓ **Q3 — Is a script acceptable here, given "no new mechanism" / "orchestrator is a
responsibility, not a component"?**: PRD §6 says OQ9 needs "no new report format, no separate
dashboard," and `ARCHITECTURE-MULTI-AGENT-WIP.md` says the design adds no new dependencies. A
read-only collector adds neither a format nor a dashboard, and sits in the same category as
`check-traceability.sh`/`wait-for-ci.sh` — but it is still new code where the design said
none was needed. Fallback if you say no: W1 becomes "post the OQ9 comment by hand for one real
work item, and record the exact procedure" — which still closes the never-instantiated gap,
but gives QA and Fullstack Developer much less to do and produces no regression protection.

➡️ **Yes, a script** — read-only, no write path, wired per `check-convention`. `wait-for-ci.sh`
is the precedent: this repo has already decided once that "encoding an agreement in a script
closes a gap a prose-only rule can't" (`CLAUDE.md`, issue #265). The same reasoning applies
to evidence collection, and it makes the pilot exercise the untested roles properly.

---

❓ **Q4 — Dogfood-only, or shipped to adopting projects?**: `adopt.sh`'s `install_skills()`
globs `skills/`, so anything placed there is symlinked into every adopted project
automatically (that is how `grilling`/`codebase-design` shipped, PR #292). That means W2's
role-contract skill would propagate to all adopted projects the moment it lands, and a
`CHANGES.md` row would be expected per `adoption-registry`. The alternative is to keep the
rollout confined to this repo until the pipeline has actually proven itself, then decide
propagation once.

➡️ **Dogfood-only for now.** No `CHANGES.md` row while the epic is in flight; add the
adoption-registry row at the end of the epic, once there is a real run to substantiate it.
Substantiating a row with "we designed it" is exactly what the substantiation requirement
exists to prevent. (This affects where W2's files live — Architect's call once you answer.)

---

❓ **Q5 — How does W1 itself enter the pipeline, given that Product has now partly run outside
it?**: This report was produced by a Product role in a co-thinking session, before any issue
or branch exists. Either (a) this report is pre-decision elaboration per Decision 5/A6, and
once you accept it, W1's issue is opened and run cleanly through all five roles from the top
— including a fresh Product phase on the work item itself; or (b) this report is treated as
W1's Product phase, and the pipeline starts at Architect.

➡️ **(a).** Decision 5 and A6 describe exactly this situation — Levels 1-2 elaboration in
`wip/<slug>/`, promoted only after your explicit acceptance. Starting the work item at
Architect would skip a role on its very first full run, which A3 forbids without your
per-instance authorization; doing that on the pilot would undercut what the pilot measures.
The re-run is cheap: this report becomes the Product phase's input, not its replacement.

---

❓ **Q6 — Create the five `role:<name>` labels now, and with which names?**: They do not exist
on the repo (verified). A5 needs them for the pilot to leave a phase trail. PRD §4 names them
`role:product`, `role:architect`, `role:qa`, `role:dev`, `role:reviewer` — note `role:dev`,
not `role:fullstack`, even though the role is "Fullstack Developer" everywhere else.

➡️ **Create all five now**, as setup for W1's pilot rather than a work item of their own, and
keep the names exactly as PRD §4 lists them — including `role:dev`. Renaming a label the
design already fixed is a gratuitous divergence; if the abbreviation bothers you, say so now,
because changing it after the pilot means editing the design documents too.

---

❓ **Q7 — What happens to #237?**: Three options: (a) leave it independent housekeeping, as
epic #65 currently frames it; (b) pull it into the new epic as a prerequisite of W2, since the
role-contract skill would otherwise ship pointing at a Dutch source of truth; (c) do it now,
before anything else. Related, and needing the same call: the `check-no-dutch.sh` permanent-vs-
pending exclusion mismatch noted in §5 — fix it inside #237, or separately?

➡️ **(b)**: keep #237 as its own issue, but record it as blocking **W2**, not the epic and not
W1. It has no bearing on W1, so it must not gate the pilot. Fold the `check-no-dutch.sh`
exclusion move (permanent → pending, then removed when #237 closes) into #237 itself, since it
is the same change's natural last step and the script's own header already prescribes that
lifecycle.

---

❓ **Q8 — Which prioritization framework?**: `ROLE-DESCRIPTIONS.md` records this as
"method TBD — e.g. an impact/effort matrix or WSJF, undecided as of 2026-09-25." I am
prioritizing right now (W1 before W2-W4), so the TBD is live rather than theoretical, and I
have used an implicit impact/effort judgment to get here. Deciding it makes that judgment
reviewable instead of tacit.

➡️ **Impact/effort matrix**, with effort supplied by the executing roles rather than by
Product (as the role contract already requires). WSJF's extra terms (time criticality, risk
reduction, job size) buy little for a single-maintainer backlog and cost a scoring ritual per
item. If you pick WSJF anyway, say so before W2 is scoped, not after.

---

### Held for round 2 (prerequisites still open)

Not asked now, because each depends on an answer above: the epic's remaining slice list and
ordering after W1 (depends on Q1/Q2); where W2's role-contract skill physically lives and
whether the five scope contracts are one skill or five (depends on Q4 and on Architect);
whether this `wip/multi-agent-rollout/` folder is promoted into `PRD.md` or kept as record
(depends on Q1, and A6 already sets the default to "kept"); and whether OQ11 resolves at the
end of W1's run or only after a second, non-meta work item has flowed through (depends on how
much signal W1's run actually produces — genuinely unanswerable before it runs).

---

## 7. Non-goals — explicitly out of scope for W1

- **No orchestrator software.** No scheduler, no state store, no routing engine, no
  persistent context object. PRD §6 and Decision 1 settled this; W1 does not nibble at it.
- **No posting, labelling, merging or any GitHub write** from the collector (R4/AC5). A2 and
  A11 are untouched.
- **No judgment.** The collector reports what evidence exists; whether a gate's evidence is
  *adequate* stays Reviewer's and Ties' call. This preserves the Overlap 2 split — structural
  by script, semantic by a role — rather than eroding it.
- **No new gates, no new report format, no dashboard.** The gate list and the table shape are
  inputs from OQ9, not choices in this work item.
- **No reopening of any closed open question.** OQ1-OQ10 stay decided. W1 instantiates OQ9; it
  does not revisit it.
- **No role-contract skill, no file-scope contracts, no security trigger list** — that is W2.
- **No `#237` translation work**, and no edits to `PRD-MULTI-AGENT-WIP.md`'s Dutch prose.
- **No edits to `PRD.md`, `ARCHITECTURE.md`, `WORKFLOW.md` or `CHANGES.md`** — A6 keeps
  unaccepted elaboration in `wip/`, and Q4 defers the adoption-registry row to the epic's end.
- **No phase-skipping, triage or scenario routing**, and no parallel role execution — A3 and
  Decision 3 rule both out for v1, and the pilot is not the place to test an exception.
- **No change to `check-traceability.sh`, `pre-merge-review` or `deploy-guards`.** They are
  reused unchanged, per OQ10 and the "System boundaries" section.
- **No claim that W1's run resolves OQ11 by itself.** W1 produces the evidence; whether it is
  enough is Ties' judgment (issue #294 AC2), and a second, non-meta work item may be needed.

---

## 8. Product-level risks

| Risk | Why it matters | Proposed handling |
|---|---|---|
| **The pilot's work item is itself about the pipeline (meta).** A run whose subject is the pipeline may flatter the pipeline — roles are unusually well-informed about the process being tested. | Could make the pilot's success non-transferable to ordinary work. | Accept for W1 (the dogfooding payoff is worth it), and treat a second, non-meta work item as the real generalization test. Named as a limitation in the pilot's own retrospective, not discovered later. Feeds Q-round-2 on OQ11. |
| **Full five-role engagement on a small script is heavy** (A3, no abbreviation in v1). | The pilot may read as bureaucratic and sour the direction on its first outing. | That weight is the point of v1 and is already a recorded, deliberate decision (issue #281). Measure it during the run — it is the evidence a later "scale engagement to the change" version would need. Do **not** quietly abbreviate mid-run; A3's hatch requires Ties' explicit per-instance authorization. |
| **Role contracts are still quoted by hand** for W1 (W2 comes later). | Fidelity depends on the orchestrator quoting correctly, which is the very failure this epic names. | Accepted for one run, and made useful: record every place the hand-assembled prompt had to invent something the contracts did not supply. That list is W2's requirements input. |
| **`ROLE-DESCRIPTIONS.md` defers to a Dutch source.** | A role resolving a discrepancy is told to read a document it may not be scoped to, in a language the rest of the repo has eliminated. | Out of scope for W1; the reason #237 is recorded as blocking W2 (Q7). |
| **Adoption blast radius** if role artifacts land in `skills/` prematurely. | `adopt.sh` globs `skills/`, so every adopted project would inherit an unproven workflow layer silently. | Q4's recommendation (dogfood-only, registry row at epic end) exists for exactly this. |
