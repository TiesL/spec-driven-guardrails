<!-- Draft issue body. Title: "[Epic] Multi-runtime orchestration: one manager over Claude Code and Codex work items". Labels: epic, process, status:backlog. Not created yet: the maintainer confirms PRODUCT-REPORT.md R3.2 first. -->

Agent: Product · Discovery · claude-opus-5-5

## Goal
One Claude Code manager session runs work items in parallel on Claude Code and Codex, so both
providers' budgets are used, work can always continue on the other provider (if need be without
the manager), and two items progress at once, while every human gate stays where it is today.

## Context / motivation
The maintainer runs SDG work on two runtimes from two macOS machines, often from a phone. Today
decisions wait unseen in separate windows, a usage limit stops work until a person notices,
runtime choice is ad hoc, and there is no single overview. Discovery record:
`wip/multi-runtime-orchestration/` (PRODUCT-REPORT.md rounds 1-3, ARCHITECT-REPORT.md,
ARCHITECT-REVIEW.md, DECISIONS.md). Evidence for #503 is not a goal; runs keep their origin
visible so they do not spoil it.

## Scope
- A canonical manager skill, loaded explicitly (never injected at SessionStart), hosted by Claude.
- Two levels: the manager runs one work-item orchestrator per item; each orchestrator does its own
  native role dispatch. `ORCHESTRATOR.md` is unchanged. Orchestrator sessions run standalone.
- A runtime session adapter (Claude `claude --bg`, Codex `codex exec`), origin recorded per run;
  operator-started sessions adopted.
- A limit ledger: Claude 5h/7d % via a user-level statusline tee, Codex via rollout `rate_limits`;
  % per item logged.
- Limits: reset ≤ X waits (X configurable, default 60 min); longer moves the item to a fresh
  orchestrator on the other runtime from artifacts, never a runtime-specific item, a non-small
  item to Codex only with weekly headroom, Reviewer follows Implementation's runtime. On a Claude
  limit or outage, Claude-side coordination including the manager waits.
- Wake via launchd (macOS only, stated as a limitation).
- Decision relay: numbered decision comment + Claude Code push; answers only in the manager chat;
  only the asking item pauses.
- Assignment: runtime-specific → that runtime; Codex only small items; else most 5h headroom;
  ≥ 90% weekly or unknown headroom gets no new item; every item sized.
- Model defaults: Claude Reviewer opus (sonnet where it clears the floor, fable when needed);
  Codex Reviewer `gpt-6.1-sol` ("high" effort an unrecorded preference). No cross-vendor Reviewer.
- Cap: 2 running work items in total, any mix, configurable; paused items do not count.
- Clone per item, lease per issue, pinned workflow source (`main`) for SDG self-development.
- Before any merge: `gh pr update-branch` + green CI on the new head, checked by the merge guard
  (base tip is an ancestor of the PR head), for `main`, release branches and adopted projects.
- A pre-given or conditional merge permission is never a confirmation of a merge into `main`.
- Visible role tag line on every agent comment (readability, not authentication).
- `capability-evidence.sh`, read-only, on demand.
- Unattended work within a pre-agreed queue or this epic's sub-issues; autonomous merge into the
  release branch allowed.
- Offer to adopted projects via `CHANGES.md` after the SDG proof run.

## Out of scope
- Merge autonomy into `main` of any kind: #511.
- A Codex-hosted manager (v1 waits for Claude).
- ID reservation or allocation for S/F/A numbers.
- Manager-level per-role dispatch; any cross-vendor Reviewer handoff.
- Estimate-based admission control.
- Splitting a work item larger than one 5h window into tasks (a later iteration).
- Non-macOS hosts.
- #499 (context budget; this epic adds nothing to the SessionStart injection), #502, #505, #507.
- Producing #503 evidence as a goal.

## Release branch (Product + Architect judgment, to be confirmed by the Architect)
Proposed: `release/<epic-number>-multi-runtime-orchestration`, forked from `main` when the
work items are created. Reasons: about ten items that deliver value only together, an unproven
manager, and unattended merges are allowed only into a release branch. Conditions:
- Membership freezes at opening: W0, W1, W3-W10. **W2 is excluded on purpose** and merges to
  `main` directly, because the merge guard that runs comes from the pinned source (`main`) and
  must be live before the first unattended merge into the release branch.
- W10 is a member but starts only after W9 passes.
- The pinned workflow source is `main`, never the release branch.
- Issues merged into the release branch are closed by hand (no auto-close off the default branch).

## Work items
- [ ] # W0 Spike: confirm the unverified runtime facts (S)
- [ ] # W1 Spec and architecture record (S)
- [ ] # W2 Merge guard: up-to-date ancestry check and post-head confirmation rule (S, targets `main`)
- [ ] # W3 Runtime session adapter for Claude and Codex (L)
- [ ] # W4 Limit ledger and per-item budget log (M)
- [ ] # W5 Clone per item, lease, pinned workflow source and cap (M)
- [ ] # W6 Manager skill: assignment, limit policy, decision relay, role tag line (M)
- [ ] # W7 Wake via launchd (M)
- [ ] # W8 `capability-evidence.sh` (M)
- [ ] # W9 SDG proof run (S)
- [ ] # W10 Offer to adopted projects via `CHANGES.md` (S)

Order: W2 any time (first); W0 → W1 → (W3, W4) → W5 → W6 → W7 → W9 → W10; W8 any time after W1.

Before the first run (maintainer action, not a work item): remove the spent Codex automation
`resume-issue-419-at-18-35`, still listed ACTIVE with a merge-carrying prompt.

Epic acceptance: AC-1..AC-16 in PRODUCT-REPORT.md R3.3, proven together by W9 (AC-13).

## Open questions
- None open. Contingent: if W0 shows Remote Control cannot push to the phone, or a
  launchd-started manager cannot be a Remote Control session, Product reopens the push channel
  (round-2 Q7) with that evidence.

## Related
**Blocked by:** none
**Blocks:** none
Out-of-scope neighbours: #511 (merge autonomy), #503 (evidence; origin kept visible), #499, #502, #505, #507.
