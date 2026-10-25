<!-- model-record: stage=Planning model="claude-opus-5-5" -->

# Architect review of the maintainer's decisions (Planning, co-thinking session)

Role: Architect. Stage: Planning. Model: claude-opus-5-5 (requested: opus). Fresh session; earlier rounds reached me only as files. Co-thinking report (A6): nothing posted, committed or switched.

**Input read (A8 floor):** `DECISIONS.md`, `PRODUCT-REPORT.md` (rounds 1-2), `ARCHITECT-REPORT.md`, `skills/role-contracts/SKILL.md` (Architect, Shared), `ORCHESTRATOR.md`, `skills/model-choice/SKILL.md`, `ARCHITECTURE.md` A33/A39, `CLAUDE.md`, `skills/release-branch-workflow/SKILL.md`. **Beyond the floor, and why:** `codex debug models` and `~/.codex/sessions/2026/10/*/*.jsonl` (model ids, `spawn_agent` arguments, effort per spawned session) and `~/.codex/config.toml` (two keys) for Q9; `~/.codex/automations/` (key names and the word "merge" only) and PR #508 / issue #503 comments for D1; `gh api` branch protection on `main`, `.github/workflows/*.yml` and `hooks/git-guardrails` (push case) for the ID rule; `claude --help` / `claude remote-control --help` for Q7. No account ids, tokens or secrets printed.

**Evidence labels:** **[V]** verified on this machine today; **[H]** help text only; **[U]** unverified, belongs in the W0 spike.

**Fact vs decision (A10).** Everything marked [V] below is a fact and is not put back to the maintainer. Section 3 holds only real decisions, max five.

---

## 1. Verdict table

| Decision | Verdict | Reason / simplest fix |
| --- | --- | --- |
| Purpose | ok, with one honesty gap | "Never dependent on one provider" is not met for Claude limits in v1 (see Q8 and Q4). Fix: state the v1 scope plainly, or pick option (b)/(c) in question 2. |
| Q1 (design both, prove on SDG) | ok | Note for W10: D3's statusline tee is a user-level change each adopter must make; say so in the offer. |
| Q2 (both origins) | ok, one gap | Does an adopted operator-started session count toward the cap of 2? Q11 says "running sessions"; default it to yes (it spends the same window). Decision-by-rule, no question needed. |
| Q3 (decision comment + push, only asker pauses) | ok | Mechanism superseded by Q7(d); the principle stands. |
| Q4 (wait ≤ X, else fresh session on other runtime) | **problem, high** | (1) The manager and every Claude worker share **one** Claude 5h/7d window [V, account-wide]. When a Claude worker hits its limit, the Claude manager is limited at the same moment, so nobody can start the Codex replacement. Under Q8a the Claude→Codex half of Q4 never fires. (2) Under D2 a "stage on the other runtime" can only mean a fresh **work-item orchestrator** on the other runtime that resumes per ORCHESTRATOR's Resume rule; the manager does no per-role dispatch. (3) Unstated precedence against Q10 (Claude-specific → Claude, Codex only small) and Q9 (no cross-vendor Reviewer). Questions 2 and 3. |
| Q5 (unattended, bounded queue, release-branch merge allowed) | ok | Matches `release-branch-workflow` (merge on CI green + tests pass). The ID-collision check must also run on these merges (see ID rule). |
| Q6 (short default profile, evidence on demand) | ok, stale line | "an opus Reviewer by default" is superseded by Q9's per-runtime defaults; Product should update the profile text and AC-11. |
| Q7(d) (Remote Control push, answer in manager chat) | **problem, medium** | Holds only while a Claude manager is alive and is a Remote Control session. (a) Under Q8a, a Claude outage means no push at all and no signal that the manager is down. (b) Each launchd wake starts a **fresh** manager, so a new Remote Control session; an answer typed into the old chat lands in a dead session. Fix: the open-decision list lives on GitHub (numbered decision comment, status open/closed); a starting manager re-pushes every open one. (c) If the maintainer answers in a Codex session directly, the manager does not see it and may re-ask or relay a second answer. Fix: a decision closes when its numbered record exists on the issue, whoever wrote it; the attended session's orchestrator records it. (d) Under Q7(d) every agent comment is posted under the maintainer's account, so an answer typed **on GitHub** cannot be authenticated. Product's AC-5 ("a comment not from the maintainer's account is never taken as an answer") is unenforceable and must become "answers count only from the manager chat or an attended session". Whether Remote Control actually pushes to the phone, and whether a launchd-started manager can be a Remote Control session, is [U] (`--remote-control` exists [H]); add both to W0. |
| Q7 role-tag question | ok to adopt, as readability only | Markers are hidden HTML comments and orchestrator/manager comments carry none, so on a phone every comment looks like the maintainer's. A visible first prose line such as `Agent: Architect · Planning · claude-opus-5-5` (manager: `Agent: manager session <id>`) is cheap: one Shared-contract sentence and one manager-skill line, no emitter or gate change (keep `model-record-emit.sh` output to one line, A31). Existing reports already do this voluntarily. It is a claim anyone can type, never authentication; absence of a tag does not mean the maintainer wrote it. |
| Q8a (manager waits while Claude is out) | **problem, medium** | It contradicts the stated purpose, and combined with the shared window (Q4) it makes v1 dependent on Claude for all coordination: no relay, no starts, no switch. Also: a launchd wake that starts a Claude manager while Claude is limited cannot spend a turn to reschedule, so the wake script itself (no LLM) must read the ledger and re-arm. Question 2. |
| Q9 (Claude: opus/sonnet/fable; Codex: "GPT-6 High") | **problem, medium** | See section 2.1. "GPT-6 High" is not a model id and maps to no single catalog entry; "High" is an effort level that native dispatch did not set in any observed spawn and that A33 neither records nor checks. Fix: name the default as a model id (recommend `gpt-6.1-sol`), treat effort as an unrecorded preference. Claude side is fine: "sonnet where it clears the floor" is model-choice's cheapest-clearing rule; opus is the fallback. Question 1. |
| Q10 (fixed order, headroom, 90% weekly gate) | ok, three gaps | (1) Precedence: does rule 1 send a **large** Codex-specific item to Codex despite "Codex gets only small items"? Default: yes (rule 1 wins), state it. (2) "Claude-/Codex-specific" needs a mechanical test, e.g. the diff's paths are only under `adapters/codex/**` vs `adapters/claude/**`; otherwise it is the manager's own judgment. (3) An `unknown` headroom reading (Claude statusline only updates while the manager renders) must fail closed: treat unknown as no headroom. All three are design defaults for W1, not questions. |
| Q11a (only running sessions count) | ok, with a consequence | Collision risk grows with **open branches**, not running sessions, and A-6 leaves paused items uncapped. Acceptable because the ID rule detects it; see ID rule for the placement fix. |
| Q12 / sizing remark | ok, one unit mismatch | Who sizes: the Architect (contract: "estimate implementation effort for Product's prioritization"), at epic split, recorded in a machine-readable place on the work-item issue (a `size:S/M/L` label or a body field), so the manager reads it rather than guessing. Q10 depends on it only at step 2, and A-5's "unsized → Claude" is a safe default. Mismatch: A-5 sizes in days (S ≤ 1 day, through the whole pipeline), the future split rule in 5h windows. Those are different units; the future iteration needs a mapping or one unit. Not blocking v1. |
| D1 (relayed verbatim confirmation, PR + SHA; no autonomy) | **problem, medium (precedent, not the rule)** | The rule is sound. The #508 precedent conflicts with it: see section 2.2. Question 5. |
| D2 (two levels, ORCHESTRATOR unchanged) | ok | Holds if Q4 is read as "switch the whole item's orchestrator". The rebase rule cannot live in ORCHESTRATOR.md under D2; see ID rule. |
| D3 (statusline tee) | ok | Write atomically (temp file + `mv`): several sessions render the same account-wide values. Readings carry `observed_at`; stale counts as unknown. |
| D4 (launchd, macOS only) | ok | |
| D5 (SDG self-development, pinned source) | ok | With a release branch, the pinned workflow source must be `main` (or a tag), never the release branch the manager is building. |
| Concurrency cap 2, any mix | ok | Parallelism spends one window faster per runtime, it adds no budget; two Claude items plus the manager share one window. Fine for v1. |
| ID rule (no reservation; rebase + fresh CI before merge) | **problem, medium** | (1) "Rebase" of a pushed PR branch needs a force-push, which the Shared contract makes human-only (A2). Use `gh pr update-branch` (merges the base into the PR branch, no force-push [H]) and wait for CI on the new head. (2) SDG's `main` already has strict required status checks (`strict: true`, context `check`, `enforce_admins: true` [V]), so GitHub already refuses a stale merge into SDG `main`. The gap is release branches (unprotected by design, and Q5 merges into them unattended) and private adopted projects (no protection). (3) Placement: D2 freezes ORCHESTRATOR.md, so put the check in the existing merge guard (`git-guardrails`, which already gates `gh pr merge` on CI + review marker): refuse when the base tip is not an ancestor of the PR head. One mechanical check covers main, release branches and adopters. Question 4. |
| Product: release branch for this epic | ok, agree | See section 2.3. |

---

## 2. Detail on the three checks that needed facts

### 2.1 Q9: "GPT-6 High" against the models on this machine

**Codex catalog on this machine** (`codex debug models`, codex-cli 0.163.0) [V]:

| slug | display name | catalog description | default effort | effort levels |
| --- | --- | --- | --- | --- |
| `gpt-6.1-sol` | GPT-6.1-Sol | latest workhorse (priority 1) | low | low … ultra |
| `gpt-6-astra` | GPT-6-Astra | frontier, most demanding work | low | low … ultra |
| `gpt-6-sol` | GPT-6-Sol | previous-generation workhorse | medium | low … ultra |
| `gpt-6-luna` | GPT-6-Luna | fast, affordable | medium | low … max |
| `gpt-5.6-sol` / `-terra` / `-luna` | GPT-5.6-* | older generation | low/medium | |
| `gpt-reserve`, `codex-auto-review` | (hidden) | | | |

**Used this month** (rollouts, `"model"` occurrences) [V]: `gpt-6.1-sol` 644, `gpt-6-sol` 357, `codex-auto-review` 334, `gpt-6-luna` 27, `gpt-6-astra` 5. `config.toml`: `model = "gpt-6-sol"`, `model_reasoning_effort = "medium"`.

**Native dispatch** [V]: all 123 `spawn_agent` calls carry only `task_name`, `fork_turns`, `model`, `message`. No effort argument was ever passed. The spawned sessions ran at each model's **catalog default**, not at the config value: 101 × `gpt-6.1-sol` at **low**, 18 × `gpt-6-sol` at medium, 3 × `gpt-6-luna` at medium, 1 × `gpt-6-astra` at low. Whether `spawn_agent` would accept an effort argument is [U] (the collaboration events carry a `reasoning_effort` field, always null; the catalog has `multi_agent_reasoning_effort: xhigh` for `gpt-6.1-sol` and `gpt-6-astra`, but no spawned session ran at xhigh). A top-level `codex exec` can take `-c model_reasoning_effort=high` [H].

**Against the maintainer's ranking.** The ranking uses ChatGPT product names ("GPT-6 Pro/Astra", "GPT-6 Extra High/High/Medium", "GPT-6 Instant", "GPT-5.6 Sol/Terra/Luna"). There is no bare "GPT-6", no "Pro" and no "Instant" in the Codex catalog, and the two models Codex actually used most (`gpt-6.1-sol`, `gpt-6-luna`) are not in the ranking. "GPT-6 High" therefore names an effort level on an unnamed model: it could mean `gpt-6.1-sol`, `gpt-6-sol` or even `gpt-6-astra` at high. "The fable equivalent is too much" most plausibly excludes `gpt-6-astra`.

**Conflict with A33.** A33/A33a: markers record the model only, the floor is judged on the model, and "the same model at a lower effort meets the floor" is an accepted risk. So a default stated as an effort level is (a) not recordable in `model-record`, (b) not checkable by any gate, and (c) on today's evidence not even applied: the Codex Reviews already on record (#489, #508, `gpt-6.1-sol`) almost certainly ran at low, its spawn default. A default that cannot be applied or observed is a wish, and the Pipeline log would show only `gpt-6.1-sol` either way. Two clean readings:

- **Recommended:** default Codex Reviewer = `gpt-6.1-sol` (the catalog's current workhorse, what Codex Implementation mostly uses, so the Review floor "at least as capable as Implementation" is met by the same model). "High" becomes a preference the orchestrator may apply when the dispatch path supports it, noted in prose per ORCHESTRATOR ("effort ... in prose ... not a marker attribute"), never a check.
- **Alternative:** if W0 shows `spawn_agent` accepts an effort, that is exactly A33's own revisit trigger ("Revisit when the dispatch tool gains an effort parameter"). Re-opening A33 for Codex would be its own decision and work item, not part of this epic.

### 2.2 D1 and the #508 precedent

Facts [V]: #503's log records that "the operator gave conditional merge permission inside the session ahead of time ('full local check approves and CI green')". The Codex automation `resume-issue-419-at-18-35` (kind `heartbeat`, rrule once at 18:35, prompt referring to "merge authorization" and "merge only if the required conditions are met") is still marked `status = "ACTIVE"`. PR #508 was merged at 19:16 local (17:16Z), about 40 minutes after that wake, at head `89827f1`, a head that did not exist when the permission was given (it came from a later update with `main`).

Assessment: the permission was conditional, given before the result existed, named no SHA, and was executed by a scheduled run. CLAUDE.md step 4 asks for confirmation "that the test succeeded and there's no regression", i.e. after the result; D1 asks for verbatim words naming PR **and head SHA**; Product's AC-9 has the adapter refuse any wake/start brief carrying merge authority. #508 would fail all three. So D1 is consistent with CLAUDE.md, but the maintainer's own recent practice is not, and the precedent is visible in #503 where a resumed orchestrator could read it as allowed. The rule needs one explicit sentence: a pre-given or conditional merge permission is not a confirmation; that form of autonomy belongs to #511. The leftover automation should be removed (spent, but still `ACTIVE`, and it carries merge authority). Both are the maintainer's actions; I changed nothing.

### 2.3 Release branch for this epic

Agree. Grounds: about ten work items that only deliver value together (adapter, ledger, wake, relay, skill), an unproven manager, and Q5's unattended merges are only allowed into a release branch, never into `main`. The holistic review before `main` is the right gate for a manager that will later run itself. Conditions to record with the Product + Architect judgment on the epic issue:

- Membership freezes at opening; W10 (offer to adopters) is a member but starts only after W9 passes (A-3).
- `main`'s strict protection does not cover `release/*`, and `ci.yml` runs on `push` only for `main`, so the ID-collision check on release-branch merges must come from the merge guard (ID rule above), not from GitHub.
- The pinned workflow source (D5) is `main`, not the release branch.
- Issues merged into the release branch must be closed by hand (skill: GitHub auto-close only fires on the default branch).
- Trade-off: no value reaches `main` until the whole epic lands. If that is too slow, the minimal slice from ARCHITECT-REPORT §6 (W0, W1, W2/W3 Codex-only, W5) could be a first release branch and the rest a second. Not a question now; Product may raise it at the stop rule.

---

## 3. Questions to put back to the maintainer (batched, A10)

1. **Q9, Codex Reviewer default.** "GPT-6 High" is not a Codex model id. Make the default `gpt-6.1-sol` (current workhorse, what Codex Reviews already used), with "high" as an unrecorded preference applied only where the dispatch path can set it (A33 records and checks the model only, and the 101 native spawns of `gpt-6.1-sol` this month all ran at low)? Or did you mean a different model (`gpt-6-sol`, `gpt-6-astra`)?
2. **Claude limits in v1.** The manager and all Claude workers share one Claude window, so when Claude is limited nothing can move Claude work to Codex, and with Q8a nothing relays or starts either. Choose: (a) accept and restate the purpose for v1 as "survives Codex limits; on a Claude limit everything waits"; (b) keep the manager on Claude but let the launchd wake script (no LLM) start a fresh Codex orchestrator for a limited Claude item; (c) Product's Q8b, a Codex-hosted manager while Claude is out.
3. **Q4 precedence.** When Q4 switches a work item to the other runtime (as a fresh work-item orchestrator resuming from artifacts), does it override Q10 ("Claude-specific → Claude", "Codex only small items"), and is a cross-vendor Reviewer then accepted for that item despite Q9's "no cross-vendor handoff"? Recommended: Q4 never moves a runtime-specific item, moves a non-small item to Codex only if Codex has weekly headroom, and the Reviewer follows the runtime that did Implementation.
4. **ID rule mechanics.** Replace "rebase" with "update the PR from its base (`gh pr update-branch`, a merge, no force-push) and wait for green CI on the new head", enforced by one merge-guard check (base tip must be an ancestor of the PR head) so it also covers release branches and unprotected adopted projects? SDG's `main` already enforces this through strict required checks.
5. **D1 and #508.** Confirm that a pre-given or conditional merge permission (as used for #508, executed by a scheduled run at a head that did not yet exist) is not a valid confirmation from now on, that #511 owns any such autonomy, and that the leftover `ACTIVE` Codex automation carrying merge authority is to be removed.

**Notes for Product (not questions):** after Q7(d)/Q8a/Q9, AC-4/AC-5 (GitHub answers cannot be authenticated; answers count only from the manager chat or an attended session), AC-8 (no Codex manager under Q8a), AC-11 (no Reviewer handoff) and the epic's scope/out-of-scope lines are stale. W0 should add: Remote Control push to phone, a launchd-started Remote Control manager, and whether `spawn_agent` accepts an effort argument.
