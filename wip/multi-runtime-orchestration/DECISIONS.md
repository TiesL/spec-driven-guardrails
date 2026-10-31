# Maintainer answers, co-thinking round 1 (2026-10-16)

The orchestrator recorded these answers to Product's Q1–Q6 (PRODUCT-REPORT.md) and the Architect's D1–D5 (ARCHITECT-REPORT.md). They are the human's decisions. Product reconciles them in Round 2.

- **Purpose (stated by the maintainer):** a manageable and scalable setup that uses the token budgets of both providers, is never dependent on one (outages), and gains speed by running sessions in parallel. #503 evidence is not a goal of this release.
- **Q1:** c. Design for both SDG and adopted projects, prove it on SDG first, then offer it via `CHANGES.md`.
- **Q2:** c. Both: the manager starts workers and also adopts operator-started sessions. Each run's origin is recorded.
- **Q3:** c, and yes. A numbered decision comment on the issue plus a push notification. Only the asking work item pauses; others continue.
- **Q4:** when a limit hits mid-stage, wait if the reset is within X. Otherwise restart the interrupted stage as a fresh role session on the other runtime, working from artifacts, and log it. X is configurable, not hardcoded (suggested default 60 minutes). Switching only at an already-finished stage boundary was rejected as rarely applicable.
- **Q5:** a, limited to a pre-agreed queue, or to an epic or release whose issues hang under one parent. Autonomous merge into a release branch is allowed (`release-branch-workflow`).
- **Q6:** c. Start from a short default profile:
  - an opus Reviewer by default;
  - Codex-specific changes go to Codex, Claude-specific changes to Claude;
  - Codex (Plus, low weekly limit) gets small items;
  - grilling can run on either.

  Budget ratio: log the % used per item on both runtimes, once Claude percentages are readable (D3), and compare after about a week. Evidence: derived on demand from GitHub artifacts by `capability-evidence.sh`, with a snapshot recorded only at revision points. Limit readings stay local per machine. Accepted "fine for now".
- **D1:** a merge confirmation may be relayed through the manager, verbatim, naming the PR and SHA. Merge autonomy into `main` stays out of this release. The merge rule stays as it is today, and the manager never adds merge authority of its own. Graduated autonomy is a separate epic: #511.
- **D2:** two levels. The manager runs one orchestrator session per work item, and each orchestrator does its own native role dispatch. `ORCHESTRATOR.md` is unchanged.
- **D3:** yes. The user-level status line also writes its input JSON to a local file, so the manager can read Claude's 5h and 7d percentages. Codex limits are read from rollout `rate_limits`.
- **D4:** both machines (Mac mini, MacBook) run macOS, so launchd is enough. "macOS only" is an explicit limitation.
- **D5:** yes, SDG self-development is in v1, with the pinned-workflow-source rule from day one.

- **Concurrency cap:** two work items at a time in total, in any mix (1 Claude + 1 Codex, 2 Claude, or 2 Codex).
- **ID collisions (S/F/A numbers) between parallel items:** no reservation or allocation mechanism in the manager; the maintainer judged that over-engineering. Roles keep picking the next free ID as today. The rule: before any merge, the orchestrator rebases the PR onto current `main` and waits for CI to be green again. CI does not re-run by itself when `main` moves, so an outdated green run could otherwise merge a duplicate. If it goes red, the item that merges second renumbers through the ordinary finding route. `check-traceability.sh` and `check-scenario-file-sync.sh` are the detection, as they were for PR #510's S305 clash.

# Maintainer answers, co-thinking round 2 (2026-10-16)

- **Q7:** d. No extra account and no extra tool. The manager pushes through Claude Code's own notification (Remote Control). The maintainer answers in the manager chat, which settles authorship, and the manager records the decision as a numbered comment on the issue. The maintainer also asked whether every role should be visibly tagged in the comments it posts under the maintainer's account (for the Architect to assess).
- **Q8:** a. Keep it simple: when Claude is out longer than X, the manager waits. "Never dependent on one provider" applies to workers in v1. During a Claude outage the maintainer works with the remaining provider directly, interacting with the work-item orchestrator sessions without the manager. The design must keep that path open: orchestrator sessions run standalone, and all state lives in artifacts.
- **Q9:** none of the options. Model defaults are defaults, not fixed choices:
  - Claude Reviewer: opus by default, sonnet where it clears the floor, fable when needed.
  - Codex Reviewer: "GPT-6 High" by default. The strongest Codex model (the fable equivalent) is too much as a default.

  The maintainer's source is an unofficial ChatGPT ranking (2026-10-16): GPT-6 Pro/Astra > GPT-6 Extra High > GPT-6 High > GPT-6 Medium > GPT-5.6 Sol tiers > GPT-6 Instant > GPT-5.6 Terra > GPT-5.6 Luna. A Codex item keeps a Codex Reviewer; no cross-vendor Reviewer handoff.
- **Q10:** a. Fixed order: Claude-specific → Claude, Codex-specific → Codex. Codex gets only small items. Otherwise the runtime with the most 5h headroom. A runtime at or above 90% of its weekly limit gets no new item.
- **Q11:** a. Only running sessions count toward the cap of 2.
- **Q12:** all ok (A-1 to A-7). Remark: every work item gets an estimated size, so none goes unsized. A future iteration (not this release) breaks a work item estimated above one 5h window into tasks. That applies to work items, not epics.
- **Request:** the Architect reviews all of the maintainer's decisions (rounds 1 and 2) for problems.

# Maintainer answers to the Architect review (ARCHITECT-REVIEW.md), 2026-10-17

All five recommendations approved:
1. **Q9 model:** the Codex Reviewer defaults to `gpt-6.1-sol` (Codex's current main model). A "high" reasoning level is an unrecorded preference, applied only where dispatch can set it (A33: markers record the model only). This replaces "GPT-6 High".
2. **Claude limit in v1:** option (a). On a Claude limit or outage, Claude-side coordination, including the manager, waits. The maintainer works directly with the remaining provider's orchestrator sessions. The purpose is restated: "never dependent on one provider" means the work can always continue on the other provider, possibly without the manager.
3. **Q4 precedence:** a limit-forced switch never moves a runtime-specific item. In v1 the automatic move is Codex → Claude only; a manual move of a non-small item to Codex requires weekly headroom. The Reviewer follows the Implementation runtime.
4. **ID rule:** replaces "rebase before merge". Before a merge, `gh pr update-branch` (no force-push), then green CI on the new head. The merge guard enforces this with one check that the base tip is an ancestor of the PR head. That check also covers release branches and adopted projects.
5. **D1 / #508:** a merge permission given in advance or on conditions no longer counts as confirmation of a merge into `main`. The confirmation must come after the final PR head is known. Any such autonomy belongs to #511. The leftover Codex automation `resume-issue-419-at-18-35` is to be removed. It has already fired (COUNT=1) and is inert, but it is still listed ACTIVE with a merge-carrying prompt.

# Observation for W1 (orchestrator, 2026-10-17)

PR #510 (#441, Codex CLI) showed the head-change gap in an honest flow. The Codex orchestrator asked for explicit confirmation at head 328b77d, and the maintainer confirmed ("Confirmed, you can merge"). The merge was then rejected because the branch was behind `main` (strict protection). Codex ran update-branch, which created a merge commit, head ea9611a, with no force-push. It ran a fresh review round on ea9611a and waited for green CI. It then merged under the earlier confirmation ("your merge authorization still applies").

Implication for the D1 rule and the ID rule: `gh pr update-branch` must run *before* the confirmation is requested, and the request must name the final head SHA. Otherwise every strict-protection repo produces this gap.

# Maintainer answers, round 3 (2026-10-17)

- **Shared-understanding statement (PRODUCT-REPORT.md R3.2):** confirmed, with one addition. `gh pr update-branch` runs *before* the merge confirmation is requested, and the request names the PR and its final head SHA.
- **P-1:** approved. W2 (the merge-guard ancestry check plus the post-head confirmation rule) is a standalone work item merged into `main` first, outside the release branch, so the check is live before the first unattended merge into the release branch.
- **P-2:** approved. In v1 the automatic limit switch runs only Codex → Claude. Claude → Codex is policy that the maintainer applies by hand.
- **P-3:** approved. Relay and manager skill are merged into W6. Create the epic and the W0–W10 issues from the drafts.
