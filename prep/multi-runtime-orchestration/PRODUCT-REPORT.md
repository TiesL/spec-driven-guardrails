<!-- model-record: stage=Discovery model="claude-opus-5-5" -->

# Product report: multi-runtime orchestration (Discovery, co-thinking session)

Role: Product. Stage: Discovery. Model: claude-opus-5-5 (requested: opus).
Status: Round 1 of grilling is open. Nothing below is decided until the maintainer answers.

**Input read (A8 floor):** the maintainer's vision (verbatim, in the dispatch prompt),
`skills/role-contracts/SKILL.md` (Product, Shared), `skills/grilling/SKILL.md`. **Read beyond
the floor, and why:** `skills/role-contracts/ORCHESTRATOR.md` (its Resume and Model-per-stage
rules constrain what "resume after a limit" may mean); `skills/model-choice/SKILL.md`
(capability-based assignment must sit inside its per-stage floor); issue #503 body and decision
#503-D1 (they fix which work runs on Codex for now and what counts as evidence). The
orchestrator's observations of today were taken as given facts. Where they are cited below they
are marked *(observed)*. I did not re-verify them in this session, and Architect's feasibility
inventory owns that check.

---

## 1. Problem statement

The maintainer runs SDG work (on SDG itself and on adopted projects) across two agent runtimes,
Claude Code and Codex (CLI and desktop). Today that takes a person at the keyboard:

- **Decisions get stuck.** A worker that needs a human decision stops and waits in its own
  window. The maintainer has to find it, read enough context to understand the question, and
  answer it there. With several sessions running, questions are missed or answered late.
- **Limits kill progress silently.** Today both Codex sessions and a Claude subagent hit usage
  limits *(observed)*. Work stops at the reset boundary and only restarts when a person notices
  and restarts it. Remaining work then sits idle for hours, often overnight.
- **Assignment is ad hoc.** Which runtime gets which issue or stage is decided by hand (for
  example #503-D1's choice of #419 and #441 for Codex). There is no stated basis for strengths,
  and remaining quota is not part of the choice.
- **No single overview.** Session state is spread over terminals, the Codex desktop app and
  rollout files. Only a read-only watcher sees it, and only on request *(observed: a Claude
  orchestrator watched Codex via `~/.codex/sessions` rollouts)*.

**Who has the problem:** the project's single human decision-maker (the maintainer), working
from more than one machine and often away from the keyboard, with a phone as the only
interface.

## 2. Desired outcomes (the maintainer's vision as checkable outcomes)

- **O1 One manager.** One Claude Code session manages the worker sessions, Claude and Codex
  alike. The maintainer talks to that session only.
- **O2 Decision relay.** Every decision a worker needs from the maintainer reaches them through
  the manager. The question is short and self-contained, can be answered from a phone, and comes
  with the worker's recommended answer. The answer reaches the worker, and the decision is
  recorded where SDG records human decisions (numbered, on the issue).
- **O3 Limit survival.** When a worker, or the manager itself, hits a 5-hour or weekly limit, the
  work is not lost. It resumes after the reset with no human action, as long as work remains
  and nothing is waiting on a human decision. Resume follows ORCHESTRATOR.md's artifact-based
  resume rule, never a restart.
- **O4 Capability-aware assignment.** Work goes to a runtime/model based on known strengths and
  weak points, within the `model-choice` per-stage floor, never below it.
- **O5 Quota-aware assignment.** Assignment takes the remaining quota of each runtime into
  account, at least so that it does not start work that will predictably die at a limit when
  another runtime has headroom.
- **Invariants (not negotiable, carried from existing decisions):** merges into `main` (and a
  release branch's merge into `main`) need the maintainer's explicit confirmation (A2, CLAUDE.md);
  the five-role pipeline and its fresh-dispatch rules stay as they are (A3); #503's evidence
  rules stay intact, so the manager must keep a run's agent-started vs operator-started origin
  visible and must not merge a partial run into a "complete" claim (#503-D1).

## 3. Design tree

Notation: **[R1]** = on the Round 1 frontier (asked below). **[A]** = depends on the
Architect's feasibility inventory (`wip/multi-runtime-orchestration/ARCHITECT-REPORT.md`, being
drafted in parallel). **[→Qn]** = waits on that Round 1 answer.

```
D0 Vision: one Claude manager over Claude + Codex workers
├── D1 Scope of first release ............................ [R1 Q1]
│   ├── D1a Which adopted projects first; per-project opt-in row in WORKFLOW-ADOPTION.md? [→Q1]
│   └── D1b Is the manager itself an SDG skill/contract (ORCHESTRATOR.md extension) or a
│           separate tool? [→Q1][A]
├── D2 Worker control model .............................. [R1 Q2]
│   ├── D2a Codex desktop: can it be agent-started at all, or only watched? [A]
│   ├── D2b Max concurrent workers; one worktree per work item [→Q2][A]
│   └── D2c How origin (agent- vs operator-started) is recorded for #503 credit [→Q2]
├── D3 Decision relay
│   ├── D3a Where questions reach the maintainer (channel) ... [R1 Q3]  (push options: [A])
│   ├── D3b What a worker does while its question is open (pause item vs keep going) [→Q3]
│   ├── D3c Batching window: relay at once vs collect for N minutes [→Q3]
│   ├── D3d Answer authorship: answer typed by maintainer vs relayed by manager, and how
│   │       that is recorded as a numbered human decision (#415 pushback flow) [→Q3]
│   └── D3e Which questions the manager may answer itself (facts, A10) vs must relay [→Q3]
├── D4 Limits
│   ├── D4a Default response when a worker hits a limit ... [R1 Q4]
│   ├── D4b Unattended resume allowed (nights, away)? ...... [R1 Q5]
│   ├── D4c Detection: Codex rollout rate_limits/credits + usage_limit_exceeded with reset
│   │       time; Claude only 429 + reset time (observed) — is Claude remaining quota
│   │       visible before a 429? [A]
│   ├── D4d Resume mechanism: `codex exec resume <id>` (observed, CLI), Codex desktop
│   │       scheduler (observed), Claude side scheduler (cloud routine / local) [A][→Q5]
│   ├── D4e The manager's own limit: who wakes the manager? [A][→Q5]
│   └── D4f The manager's own context exhaustion on long runs (artifact-based handover) [A]
├── D5 Capability-based assignment
│   ├── D5a Source of the strengths profile ............... [R1 Q6]
│   ├── D5b Granularity: per work item vs per pipeline stage (mixed runtimes in one item)
│   │       [→Q6][→Q2]
│   ├── D5c Relation to #503-D1 (Codex only on #419/#441 until the tag) [→Q6]
│   └── D5d Where the profile lives (model-choice skill? separate file?) [→Q6][A]
├── D6 Quota-aware assignment
│   ├── D6a Hard rule vs soft weight [→Q4][→Q6]
│   ├── D6b Reserve kept for the manager and for answering the maintainer [→Q4][A]
│   └── D6c Weekly vs 5h: does weekly headroom gate starting a new work item? [→Q4]
└── D7 Success measure / acceptance criteria for the first release
    └── D7a e.g. "one overnight run: limit hit, auto-resumed, one decision relayed and
            answered from phone, no lost work, no merge without confirmation" [→Q1..Q6]
```

Architect-dependent branches, summarized: D1b, D2a, D2b, D3a push options, D4c, D4d, D4e,
D4f, D5d, D6b. Product will not ask the maintainer about these until the Architect has
reported what is feasible. Several Round 2 questions will offer only the options the inventory
finds feasible.

Facts I am leaving to the Architect, not to the maintainer (A10): whether Claude Code exposes
remaining 5h/weekly quota before a 429; whether Codex desktop sessions can be started or
resumed by an agent; what scheduler can wake a Claude session after a reset (cloud routine,
launchd/cron, other); whether `codex exec resume` keeps the role's fresh-dispatch property;
what the CLI-labelled-as-"Codex Desktop" originator *(observed, CLI 0.163.0)* means for
telling the surfaces apart in evidence.

## 4. Grilling, Round 1

Frontier: decisions with no unsettled prerequisite. Six questions, all answerable with a letter
from a phone.

❓ **Q1** - **First-release scope**: Which projects does the manager run in its first release?
(a) SDG itself only; (b) SDG plus adopted projects from day one; (c) design for both, prove on
SDG first, then offer to adopted projects via `CHANGES.md`.

➡️ (c). Why: it matches the vision (both) while keeping the first proof on the repo where
breakage costs least, as with the label convention (#398).

---

❓ **Q2** - **Who starts the workers**: (a) the manager starts every worker itself
(agent-started); (b) you start workers and the manager only watches and relays; (c) both: the
manager starts workers by default, and also adopts sessions you started, recording which is
which.

➡️ (c). Why: limit resume needs agent-started runs, while #503 evidence also needs
operator-started runs, so origin must be recorded either way.

---

❓ **Q3** - **Where decisions reach you**: (a) only in the manager's own chat; (b) a numbered
decision comment on the GitHub issue (phone via the GitHub app), answered there or in chat; (c)
(b) plus a push notification (channel to be checked by the Architect). And while a question is
open: the asking work item pauses, other items continue. Yes/no?

➡️ (c) if feasible, else (b); and yes. Why: the issue comment is already SDG's durable decision
record, a push is what makes it reach a phone in time, and pausing only the asking item keeps
the rest moving.

---

❓ **Q4** - **When a worker hits a limit**: (a) wait for the reset, then resume on the same
runtime; (b) move the remaining stages to the other runtime right away; (c) (a) by default,
moving to the other runtime only at a stage boundary when that runtime clears the stage's
floor and the move does not spoil #503 evidence; (d) ask you each time.

➡️ (c). Why: resuming mid-stage on another runtime breaks fresh-dispatch and evidence, while
switching at a boundary uses idle quota with no loss.

---

❓ **Q5** - **Unattended resume**: After a reset, may the manager resume work while you are
away or asleep? (a) yes, including starting new stages and new work items from the agreed
queue; (b) yes, but only finish stages that were already in flight; (c) no, notify you and
wait. Human gates (merge into `main`, overrides, open decisions) always stop it.

➡️ (a). Why: the stated goal is to resume when work remains, and the human gates already
fence off every action that needs you.

---

❓ **Q6** - **Where knowledge of strengths comes from**: (a) a static profile we write now and
edit by hand; (b) learned only from recorded evidence (pipeline logs, findings per runtime,
#503 records); (c) start from a short static profile, revise it from recorded evidence at set
points, each revision a numbered decision.

➡️ (c). Why: there is no evidence yet to learn from, and a fixed profile would go stale and
silently override the `model-choice` floor reasoning.

---

**After Round 1:** recompute the frontier with these answers and the Architect's inventory.
Expected Round 2 topics: D3b-D3e (relay details), D4c-D4e (limit mechanics, from the feasible
options only), D5b-D5d (assignment granularity and home), D6a-D6c (quota rule), D7 (acceptance
criteria). Product writes acceptance criteria and the epic/work-item split only once the
frontier is empty and the maintainer confirms shared understanding (grilling's stop rule).
<!-- model-record: stage=Discovery model="claude-opus-5-5" -->

# Round 2 (Product, Discovery, fresh session, 2026-10-16)

Role: Product. Model: claude-opus-5-5 (requested: opus). Fresh session; rounds before this one
reached me only as files.

**Input read (A8 floor):** `skills/role-contracts/SKILL.md` (Product, Shared),
`skills/grilling/SKILL.md`, this file (round 1), `ARCHITECT-REPORT.md`, `DECISIONS.md`.
**Beyond the floor, and why:** issue #511 body (to draw the out-of-scope line exactly), #503
body and decision #503-D1 (round 1's D5c assumed it limits Codex to #419/#441; it does not, it
is a tag criterion, see below), titles of #499/#502/#505/#507 (to place them in or out of scope).

`DECISIONS.md` is authoritative. Nothing below reopens it: not the stated purpose, not the "no
ID reservation" rule, not the merge rule (D1), not the two-level shape (D2).

## R2.1 Design tree, recomputed

Legend: **closed** (by which decision or fact), **open** (on the Round 2 frontier, Qn below),
**Architect** (a "how" question, not for the maintainer, A10), **new** (branch that the
decisions themselves created).

| Node | Status | Settled by / note |
| --- | --- | --- |
| D1 scope | closed | Q1 c: design for SDG + adopted, prove on SDG, then offer via `CHANGES.md` |
| D1a first adopted project, opt-in row | closed | Ordinary `CHANGES.md` + `WORKFLOW-ADOPTION.md` row; which project is picked at offer time. Whether the offer is inside this epic: assumption A-3 in Q12 |
| D1b manager as skill vs tool | Architect | Canonical skill loaded explicitly, never injected (A39, #499 budget). Architect's recommendation stands |
| D2 worker control | closed | Q2 c, origin recorded per run |
| D2a Codex desktop startable? | closed (fact) | Observe only; the manager starts CLI sessions only |
| D2b concurrency, isolation | closed | Cap 2 in total, any mix (DECISIONS). One full clone per work item (fact: adoption refuses linked worktrees) |
| D2c origin recording | Architect | Adapter `identity()` |
| D3a channel | closed in principle, **open** in mechanism | Q3 c. Which push channel, and how an answer on GitHub is known to be the maintainer's: **Q7** |
| D3b open question pauses | closed | Q3: only the asking item pauses |
| D3c batching window | closed by default | No window: relay each "Decision needed" as it arrives; the worker itself already batches its own questions (A10). Listed as assumption A-4 |
| D3d authorship | closed | D1 + Architect R4: verbatim quote, decision number, "relayed by manager session <id>"; merge confirmation names PR and head SHA |
| D3e what the manager may answer itself | closed | Facts (A10) and existing decision-by-rule rows only. D1: "the manager never adds authority of its own" |
| D4a limit mid-stage | closed | Q4: wait if reset ≤ X (configurable, default 60 min), else fresh role session on the other runtime from artifacts, logged |
| D4b unattended | closed | Q5 a, bounded to a pre-agreed queue or one parent's sub-issues; autonomous merge into a release branch allowed |
| D4c detection | closed | D3 (statusline tee, Claude 5h/7d %) + Codex rollout `rate_limits`. Remaining [U] items go to the spike |
| D4d resume mechanism | closed | D4: launchd, macOS only |
| D4e manager's own limit | closed for "wake", **open** for "outage" | launchd wakes a fresh manager. But the purpose says "never dependent on one provider", and the manager is Claude-only: **Q8** |
| D4f manager context exhaustion | Architect | Artifact-based restart (ORCHESTRATOR Resume) |
| D5a profile source | closed | Q6 c: short default profile + on-demand `capability-evidence.sh`, snapshot only at revision points |
| D5b granularity | closed with one **new** conflict | D2: runtime chosen per work item; Q4 may move a stage. Conflict: "opus Reviewer by default" vs a Codex item whose orchestrator dispatches natively (Codex cannot natively dispatch opus): **Q9** |
| D5c relation to #503-D1 | closed (fact) | #503-D1 is a tag criterion, not an assignment limit. #503 evidence is not a goal (purpose). Invariant kept: origin visible, no partial run claimed complete |
| D5d where profile lives | Architect | Manager skill text; evidence derived by script |
| D6a hard rule vs soft weight / D6b reserve / D6c weekly gate | **open** (merged) | One lean assignment rule, or the Architect's estimate-based admission: **Q10** |
| D7 acceptance | drafted below | Confirmed at the grilling stop rule (Round 3: "confirm shared understanding") |
| N1 queue definition | closed | Q5: an explicit list recorded as a numbered decision, or one parent's open sub-issues |
| N2 paused items vs the cap of 2 | **new, open** | **Q11** |
| N3 ID collisions | closed | DECISIONS: no reservation; rebase onto current `main` + fresh green CI before any merge; second merger renumbers via the finding route. Placement of the rule (manager skill vs ORCHESTRATOR one-liner vs merge-guard check) is Architect's, given D2 says ORCHESTRATOR.md is unchanged |
| N4 SDG self-development | closed | D5: in v1, pinned workflow-source clone from day one |
| N5 "small items" for Codex | **new**, default proposed | Assumption A-5 in Q12 |
| N6 merge authority in wake prompts | closed | D1: merge rule unchanged, manager adds no authority → no wake/scheduled prompt carries merge authority. Note for the orchestrator: the #419 Codex run carried an operator-given conditional merge permission (#503 log). That is outside this epic and already contrary to CLAUDE.md step 4; not reopened here |

**Frontier after recompute:** D3a mechanism, D4e outage, D5b review conflict, D6 assignment
rule, N2 cap accounting, plus confirmation of the defaults I would otherwise silently assume
(D3c, N5, and the items in Q12). Six questions; none depends on another in this round.

## R2.2 Grilling, Round 2

Numbering continues from Round 1 so that DECISIONS entries stay unambiguous.

❓ **Q7** - **Push channel and whose answer counts**: Every agent today posts on GitHub as your
own account, so (a) GitHub never pushes you a notification for "your own" comment, and (b) the
manager cannot tell your answer from an agent's comment. Options:
(a) a second GitHub account (a machine user, collaborator on the repo) whose token the manager
gives to every session it starts. Its decision comments @-mention you, so the GitHub app on
your phone pushes natively; a reply from your own account on that comment, quoting the
decision number, is taken as your answer. Sessions you start yourself keep your account.
(b) ntfy.sh (phone app, secret topic) pushes a content-free "Decision needed on #N"; you answer
in the manager chat, and the GitHub comment is only the record.
(c) no push; you check the issue or the manager chat yourself.

➡️ (a). Why: one mechanism fixes both push and authorship with the app you already have, and
it also makes agent-started vs operator-started visible by author (Q2). Cost: one extra
account and one token per machine. Fallback if you dislike a second account: (b).

---

❓ **Q8** - **When Claude itself is out for longer than X**: The manager runs on Claude. On a
Claude limit or outage longer than X, Codex items already running continue to their own end,
but nobody relays decisions or starts the next queued item. Options:
(a) accept it: the manager waits for Claude; v1 is "never dependent" for workers only;
(b) apply Q4 to the manager too: when the wake finds Claude limited beyond X, it starts the
same manager skill on Codex, from artifacts, and hands back to Claude at the next wake when
Claude has headroom.

➡️ (b). Why: the purpose says never dependent on one provider, the policy is already canonical
(A39) so Codex can host it, and it is Q4's own rule applied once more. Cost: manager turns
spend Codex's small Plus budget; acceptable because it only happens while Claude is out.

---

❓ **Q9** - **Reviewer for a Codex work item**: Your default is an opus Reviewer, but under
D2 a Codex work-item orchestrator dispatches its roles natively, and Codex cannot dispatch
opus. Options:
(a) at the Review stage the Codex orchestrator stops with "ready for review"; the manager
starts a fresh Claude opus Reviewer on that PR. This is the manager's only per-role dispatch;
the Codex orchestrator resumes for routing findings;
(b) opus is the default for Claude items only; Codex items use Codex's strongest model as
Reviewer (floor: at least as capable as Implementation);
(c) the Codex orchestrator calls the Claude CLI itself for the Reviewer.

➡️ (a). Why: it keeps your opus default and adds cross-vendor independence, spends Claude
budget on the cheap-per-token end of a Codex item, and keeps ORCHESTRATOR.md's role rules
unchanged (the handoff is one adapter line, Architect to confirm). If Claude is limited, Q4
applies and (b) is the fallback.

---

❓ **Q10** - **Assignment rule**: Which runtime gets the next queued item?
(a) a fixed order, no cost estimates: 1) Claude-specific change → Claude, Codex-specific →
Codex; 2) Codex only if the item is "small" (Q12 A-5); 3) otherwise the runtime with more
5h headroom; a runtime at or above 90% weekly gets no new item. Limit hits mid-work are
handled by Q4 only.
(b) (a) plus the Architect's admission check: estimate each stage's cost from past token
medians and do not start a stage that will not fit in the current window.

➡️ (a). Why: it uses both budgets with readings we already have; (b) needs a token-to-percent
model the Architect marks as approximate, and Q4 already covers a mid-stage hit. Revisit with
a week of the per-item % logs (Q6).

---

❓ **Q11** - **Do paused items count against the cap of 2?** An item waiting on your decision,
or waiting ≤ X for a reset, holds no session. Options:
(a) no: only running sessions count, so the manager starts the next queued item while one
waits on you; (b) yes: two waiting items stop the queue.

➡️ (a). Why: "others continue" (Q3) and parallel speed are the purpose. Cost: more open
branches at once, so more of the renumbering that DECISIONS already accepts. The number of
paused items is not capped (assumption A-6 lets you set one).

---

❓ **Q12** - **Confirm the defaults I would otherwise assume** (answer "all ok" or name the
ones to change):
- A-1 Cap 2 and X (default 60 min) are both configurable values, not hardcoded.
- A-2 macOS only (launchd), stated as a limitation in the docs.
- A-3 The `CHANGES.md` offer to adopted projects is the last work item of this epic, started
  only after the SDG proof run (AC-13) passes.
- A-4 Decisions are relayed as they arrive, no batching window.
- A-5 "Small" (for Codex) = sized S (≤ 1 day) in the epic's work-item split; an item with no
  size goes to Claude.
- A-6 No cap on paused items.
- A-7 The manager always works from one parent epic or an explicit queue you gave it; it never
  picks up unqueued `status:backlog` issues by itself.

➡️ All ok. Why: each is the simplest reading of a decision already taken, and each can change
later without redesign.

## R2.3 Epic draft (provisional until Round 2 is answered and shared understanding confirmed)

Items depending on a Round 2 answer are tagged **[Q7]**…**[Q12]**, written per the
recommended answer.

### Goal

One Claude Code manager session runs SDG work items in parallel on Claude Code and Codex, so
that both providers' budgets are used, no single provider's limit or outage stops the work,
and two items progress at once, while every human gate stays where it is today.

### Scope

- A canonical manager skill (loaded explicitly, not injected), hosted by Claude, and by Codex
  while Claude is out beyond X **[Q8]**.
- A runtime session adapter for Claude (`claude --bg`) and Codex (`codex exec`), with origin
  recorded per run; adopting operator-started sessions read-only.
- A limit ledger: Claude 5h/7d % via the statusline tee (D3), Codex via rollout `rate_limits`,
  per-item % logged.
- Limit handling per Q4, unattended within a bounded queue per Q5, wake via launchd.
- Decision relay: numbered decision comment + push **[Q7]**; only the asking item pauses.
- Assignment by the default profile (Q6) and the lean rule **[Q10]**; cap 2 running **[Q11]**.
- Clone per work item, lease per issue, pinned workflow source for SDG self-development (D5).
- Rebase onto current `main` + fresh green CI before any merge (ID-collision rule).
- `capability-evidence.sh`, read-only, on demand.
- Offer to adopted projects via `CHANGES.md` after the SDG proof **[Q12 A-3]**.

### Out of scope

- Merge autonomy into `main` of any kind: #511. The merge rule stays as today; a relayed
  confirmation is only the maintainer's verbatim words naming PR and SHA (D1).
- Non-macOS hosts (no Linux/Windows wake).
- ID reservation or allocation for S/F/A numbers (DECISIONS).
- Manager-level per-role dispatch, except the single Reviewer handoff **[Q9]**.
- Producing #503 evidence as a goal (runs keep origin visible so they do not spoil it).
- Estimate-based admission control **[Q10]**.
- #499 (context budget), #502, #505/#507: separate issues; this epic must not add to the
  SessionStart injection.
- Changes to ORCHESTRATOR.md's role-dispatch rules (D2).

### Outcomes

- **O1** One manager; the maintainer talks to it only (plus phone answers on GitHub).
- **O2** Every human decision reaches the phone, answered once, recorded as a numbered decision.
- **O3** No work stops for a provider's limit or outage longer than X while the other has headroom.
- **O4/O5** Both budgets are used per the profile and headroom rule; % per item is logged.
- **O6** Two items progress in parallel without a merge ever skipping today's gates.

### Acceptance criteria

- **AC-1 (start, origin).** Given a queue with two items, when the manager starts them, then
  each runs in its own clone as one work-item orchestrator, and its Pipeline log records the
  runtime, model, session/thread id, origin `agent-started` and workflow-source SHA.
- **AC-2 (adopt).** Given a session the operator started, when the manager adopts it, then it
  is recorded `operator-started` and the manager starts nothing on that issue (lease).
- **AC-3 (cap).** Given 2 running sessions and a third queued item, when nothing pauses, then
  the third is not started; when one item pauses on a decision, then it is started **[Q11]**.
- **AC-4 (relay).** Given a worker stops with a question, when the manager detects it,
  then an open numbered decision comment with the worker's recommended answer appears on the
  issue, the maintainer gets a Claude Code push, and only that item pauses. A freshly started
  manager re-pushes every open decision.
- **AC-5 (answer).** Given an open decision, when the maintainer answers in the manager chat,
  then the answer is recorded verbatim with "relayed by manager session <id>" and the item
  resumes; a GitHub comment is never taken as an answer; a decision already closed by a record on
  the issue (for instance from an attended session) is not asked or relayed again.
- **AC-6 (short limit).** Given a stage hits a limit whose reset is ≤ X, when the manager reads
  the ledger, then the item waits and resumes on the same runtime after the reset with no human
  action, and the wait is logged.
- **AC-7 (long limit).** Given the reset is > X (or unknown) and the other runtime has
  headroom, then the interrupted stage restarts as a fresh role session on the other runtime
  from artifacts, never a resumed Reviewer, and the switch is logged.
- **AC-8 (manager down).** Given the manager's own Claude limit or outage, when launchd wakes
  it, then a fresh manager resumes from artifacts and the ledger only, on Claude if within X,
  otherwise on Codex **[Q8]**.
- **AC-9 (no merge authority).** Given any wake, resume or start brief, when it contains merge
  authority into `main`, then the adapter refuses to send it; and no merge into `main` happens
  without the maintainer's verbatim confirmation naming PR and head SHA.
- **AC-10 (pre-merge rebase).** Given two parallel items took the same S/F/A ID, when the second
  is about to merge, then it has been rebased onto current `main`, CI has re-run green on the
  new head, and if traceability/scenario-sync checks went red it was renumbered via the finding
  route before the merge.
- **AC-11 (assignment).** Given a queued item, when the manager assigns it, then the Pipeline
  log names the rule step that decided it (runtime-specific, small→Codex, headroom, weekly gate)
  and the opus Reviewer default is applied, with the Codex-item Reviewer handoff **[Q9, Q10]**.
- **AC-12 (budget log).** Given an item finishes, then the % used of each runtime's 5h and 7d
  window during that item is logged, or `unknown`, never 0, when a reading is missing.
- **AC-13 (SDG proof).** Given a queue of at least three real SDG items on one machine,
  unattended overnight, when one limit hits and one decision is answered from the phone, then
  all items reach an open PR with an approving review or a recorded human stop, no work is lost,
  and nothing merged into `main` without confirmation.
- **AC-14 (offer).** Given AC-13 passed, then `CHANGES.md` offers the manager with an
  opt-in row, "macOS only" stated, and SDG's pinned-source rule documented for adopters **[Q12]**.

### Candidate work-item split (adapted from Architect W0-W9)

Release-branch use: recommended (many items, an unproven manager, autonomous merge into a
release branch allowed by Q5); a Product + Architect judgment to record per `release-branch-workflow`.

| # | Item | Purpose | Size (Architect's) | Codex-eligible (A-5) |
| --- | --- | --- | --- | --- |
| W0 | Spike | Confirm the [U] facts: `codex exec` success-path `rate_limits`, resume after reset, `claude --bg --resume` after a limit, statusline reset times, machine-user token in `gh` **[Q7]** | S | no (Claude needed for half) |
| W1 | Spec and decisions | PRD epic section, scenarios, A40 (modules, seams), "limited ≠ unavailable", no-merge-authority rule, placement of the rebase rule | S | no |
| W2 | Runtime session adapter | start/status/resume/identity for Claude and Codex, origin, stdin quirk, refuse merge-authority briefs, never resume a Reviewer | M–L | no |
| W3 | Limit ledger | Normalized 5h/7d readings from Codex rollouts, the Claude statusline tee (D3) and transcript fallback; per-item % log; fail closed | M | partly (Codex reader) |
| W4 | Wake | launchd one-shot; fresh manager from artifacts; Codex host when Claude is out > X **[Q8]** | M | no |
| W5 | Decision relay | "Decision needed" format, numbered decision comment, push, answer authenticity, verbatim relay incl. merge confirmation **[Q7]** | S–M | yes |
| W6 | Clones, lease, pinned source | Clone per item, lease in Pipeline log + `status:in-progress`, pinned workflow source, cleanup, cap 2 **[Q11]** | M | no |
| W7 | `capability-evidence.sh` | Read-only per (runtime, model, stage) evidence with n, no ranking | M | yes |
| W8 | Manager skill | Canonical policy: queue, profile, assignment rule **[Q10]**, Q4 wait-or-switch with X, Q5 bounds, Codex Reviewer handoff **[Q9]**; adapter mapping lines | S | no |
| W9 | SDG proof run | Run AC-13 and record it | S (ongoing) | n/a |
| W10 | Offer to adopted projects | `CHANGES.md` entry and adoption docs, after W9 **[Q12 A-3]** | S | yes |

Dropped against the Architect list: Linux wake (D4), ID reservation (DECISIONS), manager-level
per-role dispatch beyond the Reviewer handoff (D2), cost-estimate admission (if Q10 a), #503 as
W9's purpose (purpose statement). Order: W0 → W1 → (W2, W3) → W5 → W6 → W4 → W8 → W9 → W10;
W7 any time after W1.

**Next step:** the maintainer answers Q7-Q12. Round 3 is then expected to be only the
grilling stop rule: confirm shared understanding of this draft, after which the epic and
work-item issues are written.
<!-- model-record: stage=Discovery model="claude-opus-5-5" -->

# Round 3 (Product, Discovery, fresh session, 2026-10-17)

Agent: Product · Discovery · claude-opus-5-5 (requested: opus). Fresh session; earlier rounds
reached me only as files.

**Input read (A8 floor):** `skills/role-contracts/SKILL.md` (Product, Shared),
`skills/grilling/SKILL.md`, `skills/write-spec/SKILL.md`, `templates/ISSUE_TEMPLATE/`
(epic, work-item), this file (rounds 1-2), `ARCHITECT-REPORT.md`, `ARCHITECT-REVIEW.md`,
`DECISIONS.md`. **Beyond the floor, and why:** `skills/release-branch-workflow/SKILL.md` (to
place the merge-guard item relative to the frozen membership set); titles and labels of #511,
#503, #502, #505, #507, #499 (scope lines); `gh label list` (no `size:*` label exists yet, so
the size goes in the issue body until the Architect picks a machine-readable place).

`DECISIONS.md` is authoritative and is not reopened here.

## R3.1 Frontier, recomputed

Every node open after Round 2 is closed:

| Node | Closed by |
| --- | --- |
| D3a push mechanism and answer authenticity | Q7 d: Claude Code notification (Remote Control); answers count only from the manager chat (or an attended orchestrator session). A GitHub comment is never an answer, since all agents post as the maintainer's account (Architect review) |
| D4e Claude outage | Q8 a + review answer 2 (a): Claude-side coordination, the manager included, waits; the maintainer drives the remaining provider's orchestrator sessions directly. Purpose restated: work can always continue on the other provider, possibly without the manager |
| D5b Reviewer for a Codex item | Q9 + review answer 1: Codex Reviewer `gpt-6.1-sol`, Claude Reviewer opus (sonnet where it clears the floor, fable when needed); effort "high" is an unrecorded preference; no cross-vendor Reviewer |
| D6 assignment rule | Q10 a, plus review answer 3 (Q4 precedence) |
| N2 paused items vs cap | Q11 a. Adopted operator-started running sessions count too (decision-by-rule, Architect review) |
| N3 ID collisions | Review answer 4: `gh pr update-branch` + green CI on the new head, enforced by a merge-guard ancestry check |
| N6 merge authority | D1 + review answer 5: a pre-given or conditional permission is no confirmation; confirmation comes after the final head is known |
| Q12 defaults A-1..A-7 | All ok; every work item sized |
| Role tag line | Maintainer asked, Architect assessed it as cheap readability (not authentication); taken in as AC-15 |

**Decisions Product takes here (scope/trade-off, my own remit, stated for confirmation in the
statement below, not as questions):**
- **P-1 Merge-guard item outside the release branch.** The ancestry check and the "no pre-given
  confirmation" sentence (W2) target `main` directly and are not members of the release branch.
  Reason: the guard that runs is the one from the pinned workflow source (`main`), and it must be
  live before the first unattended merge into the release branch. Linked to the epic, excluded
  from the frozen membership set at opening.
- **P-2 Q4 in v1 is exercised one way only.** One Claude window is shared by the manager and all
  Claude workers (Architect [V]), and the manager waits while Claude is out. So the automatic
  switch in v1 is Codex item → fresh Claude orchestrator. The Claude → Codex direction is written
  in the canonical policy (with review answer 3's precedence) for the maintainer's manual path,
  not automated.
- **P-3 W5 relay and W8 skill merged** into one manager-skill item; W2 (adapter) stays one item,
  size L, which the Architect may split at Planning.

**Not questions (facts or the Architect's "how", A10):** where the size is stored, the
mechanical test for "Claude-/Codex-specific", unknown headroom failing closed, atomic statusline
tee, the wake script re-arming without an LLM, open decisions living on GitHub and being
re-pushed by a fresh manager.

**Contingent re-entry, not asked now:** if W0 shows that Remote Control cannot push to the phone,
or that a launchd-started manager cannot be a Remote Control session, Product reopens Q7 with that
evidence. Until then Q7 d stands.

**Frontier: empty.** No question for the maintainer in this round.

## R3.2 Shared understanding (grilling stop rule, for the maintainer to confirm)

> One Claude Code manager runs at most 2 work items at a time (any mix, configurable; paused items do not count), each as a standalone work-item orchestrator in its own clone, started by the manager or adopted from the operator, origin recorded.
> Assignment: runtime-specific → that runtime; Codex only small (S) items; else most 5h headroom; ≥ 90% weekly or unknown headroom gets no new item; unsized → Claude.
> A limit with reset ≤ X (configurable, default 60 min) waits; longer moves the item, never a runtime-specific one, to a fresh orchestrator on the other runtime from artifacts; non-small to Codex only with weekly headroom; the Reviewer follows Implementation's runtime.
> In v1 a Claude limit or outage stops the manager too: Claude-side coordination waits and the maintainer drives the Codex orchestrators directly, which works because all state lives in artifacts.
> Reviewer defaults: Claude opus (sonnet where it clears the floor, fable when needed); Codex `gpt-6.1-sol`, "high" effort only where dispatch can set it, unrecorded. No cross-vendor Reviewer.
> A worker's question becomes a numbered decision comment plus a Claude Code push; you answer in the manager chat only; only that item pauses; a fresh manager re-pushes open decisions.
> Every agent comment opens with a visible tag line (`Agent: <role> · <stage> · <model>`), readability only.
> Merges into `main` keep today's rule: your confirmation after the final head is known, naming PR and SHA. Pre-given or conditional permission never counts (#511 owns autonomy). The leftover Codex automation is removed.
> Before any merge: `gh pr update-branch`, green CI on the new head, and the merge guard checks ancestry. That item goes to `main` first, outside the release branch.
> The rest of the epic lands on `release/<epic>-multi-runtime-orchestration`, unattended merges allowed there, proven on SDG by an overnight run (pinned source = `main`), then offered to adopters via `CHANGES.md`. macOS only (launchd).
> Out: merge autonomy (#511), ID reservation, a Codex-hosted manager, estimate-based admission, splitting large items into tasks (later).

## R3.3 Final acceptance criteria (epic level)

Delivered by the work item named in brackets; each work-item file restates its own share in
Given/When/Then. Supersedes R2.3's AC list.

- **AC-1 Start and origin [W5, W3].** Given a queue with two items, when the manager starts
  them, then each runs in its own clone as one work-item orchestrator, and its Pipeline log
  records runtime, model, session/thread id, origin `agent-started` and workflow-source SHA.
- **AC-2 Adopt [W3, W5].** Given a session the operator started, when the manager adopts it,
  then it is recorded `operator-started`, holds the issue's lease, and counts toward the cap
  while it runs.
- **AC-3 Cap [W5, W6].** Given 2 running sessions (any mix) and a third queued item, when
  nothing pauses, then the third is not started; when one item pauses on a decision or a
  wait ≤ X, then it is. The cap is a configurable value.
- **AC-4 Relay [W6, W3].** Given a worker stops with a question, when the manager detects it,
  then an open numbered decision comment with the worker's recommended answer appears on the
  issue, the maintainer gets a Claude Code push, and only that item pauses. A freshly started
  manager re-pushes every open decision.
- **AC-5 Answer [W6].** Given an open decision, when the maintainer answers in the manager chat,
  then the answer is recorded verbatim with "relayed by manager session <id>" and the item
  resumes; a GitHub comment is never taken as an answer; a decision already closed by a record on
  the issue (for instance from an attended session) is not asked or relayed again.
- **AC-6 Short limit [W4, W6, W7].** Given a stage hits a limit whose reset is ≤ X, then the
  item waits and resumes on the same runtime after the reset with no human action; the wait is
  logged.
- **AC-7 Long limit [W6, W3].** Given a Codex item's reset is > X or unknown, the item is not
  Codex-specific and Claude has headroom, then a fresh Claude work-item orchestrator resumes it
  from artifacts (ORCHESTRATOR Resume), never a resumed Reviewer, and the switch is logged. A
  runtime-specific item is never moved; a non-small item moves to Codex only with Codex weekly
  headroom; the Reviewer follows the Implementation runtime.
- **AC-8 Claude out [W7, W6].** Given Claude is limited or out longer than X, then no Codex
  manager starts; the wake script (no LLM) reads the ledger and re-arms; running Codex
  orchestrators continue; and the maintainer can drive any orchestrator session directly with no
  state held only by the manager.
- **AC-9 No merge authority [W2, W3, W6].** Given any start, resume or wake brief that carries
  merge authority into `main`, then the adapter refuses to send it; and no merge into `main`
  happens on a pre-given or conditional permission, only on the maintainer's verbatim
  confirmation naming PR and head SHA, given after that head exists.
- **AC-10 Up to date before merge [W2].** Given a PR whose base tip is not an ancestor of its
  head, when anyone runs `gh pr merge` (into `main`, a release branch, or in an adopted
  project), then the merge guard refuses; after `gh pr update-branch` and green CI on the new
  head it allows it; a red traceability/scenario-sync check is fixed by renumbering through the
  finding route.
- **AC-11 Assignment and models [W6].** Given a queued item, when the manager assigns it, then
  the Pipeline log names the rule step that decided it (runtime-specific, small → Codex,
  headroom, weekly gate, unknown = no headroom, unsized → Claude) and the Reviewer default for
  that runtime (Claude opus, sonnet where it clears the floor, fable when needed; Codex
  `gpt-6.1-sol`).
- **AC-12 Budget log [W4].** Given an item finishes, then the % of each runtime's 5h and 7d
  window used during it is logged, or `unknown` (never 0) when a reading is missing.
- **AC-13 SDG proof [W9].** Given a queue of at least three real SDG items on one machine,
  unattended overnight, when one limit hits and one decision is answered from the phone, then
  every item is merged into the release branch or reaches an open PR with an approving review,
  or stops with a recorded human stop; no work is lost; nothing merged into `main`.
- **AC-14 Offer [W10].** Given AC-13 passed, then `CHANGES.md` offers the manager with an
  opt-in row, stating macOS only, the user-level statusline tee each adopter must make, and the
  pinned-source rule.
- **AC-15 Visible role tag [W6].** Given any role, orchestrator or manager posts a comment, then
  its first prose line is `Agent: <role> · <stage> · <model>` (manager: `Agent: manager session
  <id>`); documented as readability, not authentication.
- **AC-16 Sized items [W1, W6].** Given the epic's queue, then every work item carries an
  estimated size the manager reads; an unsized item is treated as not small.

## R3.4 Draft files

Written under `wip/multi-runtime-orchestration/issues/`: `epic.md` and W0-W10 (W5/W8 of
Round 2 merged into W6; W2 is the new merge-guard item; numbering below supersedes R2.3).
Proposed release branch: `release/<epic-number>-multi-runtime-orchestration`.

**Next step:** the maintainer confirms R3.2 (or corrects it). Then the orchestrator creates the
epic and work-item issues from the drafts, the Architect records the release-branch judgment on
the epic, and Covers tokens are assigned.
