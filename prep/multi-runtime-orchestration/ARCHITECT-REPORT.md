<!-- model-record: stage=Planning model="claude-opus-5-5" -->

# Architect report: multi-runtime orchestration (Planning, co-thinking session, feasibility inventory)

Role: Architect. Stage: Planning. Model: claude-opus-5-5 (requested: opus). Co-thinking session (A6): this file is the report. Nothing posted, committed or switched.

**Scope read (A8, floor).** Named: `skills/role-contracts/SKILL.md` (Architect, Shared), `skills/role-contracts/ORCHESTRATOR.md`, `ARCHITECTURE.md` A39, `adapters/*/INSTRUCTIONS.md`, issue #503. I also read the following, because the question asks what is verifiable on this machine: `adopt.sh` (adoption guard), `lib/codex-adoption.py` and `lib/claude-status.py` (the `.git` checks), the `codex`/`claude` CLI help, `~/.codex/sessions/2026/10/**` rollout files, `~/.codex/automations/`, `~/.codex/config.toml` (key names only), `~/.claude/jobs/*/state.json`, `claude agents --json`, the Claude transcripts for this project (searched for limit errors only), the Pipeline logs on #419 and #453, the `model-record` markers on PRs #489/#493/#495/#497/#506/#508, and `review-rounds.sh 489 455`. I printed no secrets, account ids or tokens. I ran one live probe: `codex exec --json --ephemeral -s read-only` in my scratchpad, which hit the current Codex limit (see §2).

**Evidence labels in this file.** **[V]** means verified on this machine today. **[H]** means read from the help text only, not exercised. **[U]** means unverified, a spike item.

---

## 0. Summary of the shape I recommend

Use two levels, and keep the existing orchestrator intact:

```
human ──► Manager session (Claude Code, long-lived, restartable from artifacts)
              │  Runtime Session Adapter (Seam, 2 real adapters: claude, codex)
              ├──► work-item orchestrator session A  (Claude: claude --bg, own clone)
              │       └─ native fresh role dispatch (Agent tool)            ← ORCHESTRATOR.md unchanged
              └──► work-item orchestrator session B  (Codex: codex exec / resume, own clone)
                      └─ native fresh role dispatch (Codex thread_spawn)    ← ORCHESTRATOR.md unchanged
          Limit Ledger (reads both runtimes' limit signals)  ·  Wake (OS-level one-shot, survives the manager)
```

The Manager is a new **Module** above the per-work-item orchestrator. It is not a replacement for it. It owns four things: which work item runs where and on which runtime, the relay of human decisions, limit-aware admission and pause, and the wake after a reset. Role dispatch, freshness, finding routes and markers stay in `ORCHESTRATOR.md`, which gives that rule set the most **Locality**. Both runtimes can already do fresh child dispatch natively (§1). So the Manager does not need to dispatch individual roles in v1.

---

## 1. Delegation channels

| Channel | Who starts it | Can it ask the human and get an answer? | Resumable? | Observed how | #503 attribution it yields |
| --- | --- | --- | --- | --- | --- |
| **Claude Agent tool subagent** (in-process) | The calling Claude session | No direct ask. It returns a report and ends. The parent can continue it with `SendMessage` (the ORCHESTRATOR forbids this for a Reviewer). | Only while the parent session lives. It dies with the parent and shares the parent's account limit. | Agent id returned to the parent. Pipeline log line (#453 log [V]: `agent ab30e1050cafdf0bc, model sonnet`). | Agent id plus requested model in the Pipeline log, and the role's own `model-record`. Parentage is implicit (same transcript). This is today's dispatch path. |
| **Separate Claude session, background** (`claude --bg`, `claude agents`, `attach/logs/stop`) | The Manager (CLI) or the operator | Indirectly. The session goes to `state:"blocked"` with a `detail` string. [V] In `~/.claude/jobs/*/state.json`: `"detail":"Architect review complete; 3 decisions need user confirmation"`, `tempo:"blocked"`. `--brief` enables a `SendUserMessage` tool [H]. The answer goes back through `--resume <id>` or `attach`. | Yes. `--bg --resume <session-id>` continues under the same id [H]. Behavior when it is resumed after a limit is [U]. | `claude agents --json` [V] (fields `cwd,id,kind,name,pid,sessionId,startedAt,state,status`). `state.json` has `state`, `detail`, `tokens`, `children` [V]. `timeline.jsonl` shows working/blocked/done transitions [V]. | Session id, cwd, cliVersion, `tokens`, child count, and `resumeSessionId` for resume lineage [V, key names]. That is stronger parentage than an in-process subagent. |
| **Separate Claude session, interactive** (operator's terminal) | The operator | Yes, the human is present | `claude --resume`/`--continue` | The transcript JSONL under `~/.claude/projects/...` | Same as the row above, but the operator is the author of every human answer. |
| **`codex exec`** (headless) | The Manager | No. It runs one turn and ends. The question shows up as the final message (`-o <file>` [H], or `task_complete.last_agent_message` in the rollout [V field]). The answer goes back with `codex exec resume <thread_id> "<answer>"` [H]. `codex queue --thread <id> --message` [H] queues a message to an existing session over the app-server; whether that reaches an exec thread is [U]. | Yes, through `exec resume <id>` or `--last` [H]. A resume after a limit reset is [U] (Codex is limited until 18:34 today). | `--json` stdout events [V: `thread.started{thread_id}`, `turn.started`, `error`, `turn.failed`]. Rollout file `~/.codex/sessions/Y/M/D/rollout-*.jsonl` (unless `--ephemeral`) [V]. `codex agents` lists sessions on the local app-server daemon [H]. | `session_meta` [V]: `originator`, `source:"exec"`, `cli_version`, `cwd`, `git`, `thread_source`. That covers #503's surface, version and project fields directly. |
| **Codex native subagents** (from a Codex orchestrator) | A Codex session | No, they report to the parent thread | Through the parent | Rollout `session_meta.source.subagent.thread_spawn` [V] with `parent_thread_id`, `depth`, `agent_path` (e.g. `/root/architect_419`) and `agent_nickname`. 119 such spawns this month (TUI and desktop). | Exact child identity and parentage, which #503 asks for. The #419 Pipeline log already uses `agent_path` as the agent id [V]. |
| **Interactive Codex CLI/desktop** (operator-started) | The operator | Yes, the human is present | `codex resume`. Desktop "heartbeat" automations can re-prompt a thread [V, §2]. | Read-only rollout files, `codex agents` | `originator:"Codex Desktop"` or `codex-tui`, `source:"vscode"` [V]. The operator authors the answers. |

**Constraint found [V]:** `codex exec` with no TTY prints `Reading additional input from stdin...` and waits. The adapter must pass `</dev/null`, or pass the prompt with `-`, or the session hangs.

**Consequence for "relay decisions":** none of the headless channels can hold a question open. Every channel above, except a human-attended session, has the same shape: the session stops with a question, the Manager detects it, the human answers, and the Manager resumes the session with the answer. This is a real **Interface** that both runtimes implement differently, which is the two-adapters rule satisfied.

---

## 2. Limit signals

### Codex: rich, structured, proactive [V]

Every `event_msg/token_count` in a rollout carries:

```json
"rate_limits": {"limit_id":"codex",
  "primary":   {"used_percent":99.0, "window_minutes":300,   "resets_at":<epoch>},
  "secondary": {"used_percent":60.0, "window_minutes":10080, "resets_at":<epoch>},
  "credits":{...}, "plan_type":"plus", "rate_limit_reached_type":null}
```

and `info.total_token_usage` / `last_token_usage`, plus a separate `token_usage_record` with per-turn, per-thread and per-session usage. Across this month there are 4,466 such records with the 300 and 10080 windows, which are the 5h and weekly windows. Reset epochs observed today: 5h at 2026-10-16 18:34, weekly at 2026-10-22 12:48. Running out shows up as `task_complete.error.codex_error_info:"usage_limit_exceeded"`. There were 14 of these this month, alongside `server_overloaded` (3) and `unauthorized` (1), which the Manager must not treat as the same thing.

**Gap [V]:** in `codex exec --json` stdout, the limit hit appears only as `turn.failed{error.message:"…try again at 6:34 PM."}`, with exit code 1. There is no error code and no epoch. The structured code and `resets_at` live in the rollout file, and an `--ephemeral` run has none. The adapter should therefore not use `--ephemeral`, and should read the newest rollout for that `thread_id`. Whether a successful `--json` stream carries `token_count`/`rate_limits` is [U]. The success path could not be probed today. `rate_limit_reached_type` was null in every record, including the ones next to the 99% reading, so I cannot say what fills it [U].

### Claude: weaker, partly human-text

- **On a hit [V]:** transcript records carry `error:"rate_limit"`, `isApiErrorMessage:true`, with text such as `You've hit your session limit · resets 3:10am (Europe/Amsterdam)` and `You've hit your weekly limit · resets Oct 5 at 4am (Europe/Amsterdam)`. That is parseable, but it is a locale- and format-dependent string. Treat it as fragile and fail closed: if it cannot be parsed, record the reset as unknown, never as "now".
- **Before a hit [V, field names only]:** the user's `statusLine` command reads `.rate_limits.five_hour.used_percentage` and `.rate_limits.seven_day.used_percentage` from Claude Code's statusline input. So the data exists in-process. Whether a reset timestamp is included is [U]. The data reaches a file only if the statusline command tees its stdin, which is a user-settings change and needs the maintainer's say. It only updates while an interactive session renders, so a fully headless Manager would not see it [U for `--bg`].
- **Per-session cost [V]:** `~/.claude/jobs/*/state.json` has `tokens` (e.g. 867186, 313847, 324695). These are useful as a cost-per-work-item history, but they are tokens, not a percentage of a limit.
- **Status command:** `/usage` exists interactively. I found no headless machine-readable equivalent [U].

### Scheduling a resume

| Mechanism | Survives the session? | Notes |
| --- | --- | --- |
| Claude `CronCreate` / `/loop` | No, it is session-only | Useless across a Claude limit, which is exactly when the Manager itself is stopped |
| Claude cloud routines (`schedule` skill) | Yes | Runs in the cloud. It has no access to local clones, `~/.codex` or local Codex auth. Not suitable for this. |
| Codex Desktop automations [V] | Yes, while the desktop app runs | `~/.codex/automations/<id>/automation.toml`: `kind="heartbeat"`, `rrule="FREQ=DAILY;COUNT=1;BYHOUR=18;BYMINUTE=35"`, `target_thread_id`, `prompt`. One was created today about 30 seconds before the recorded `usage_limit_exceeded`. It resumes **Codex** threads only. |
| Codex CLI | None | |
| OS one-shot (macOS `launchd` plist / `at`) | Yes | It is the only option that can wake a **Claude** Manager after a Claude limit. It is machine-local and macOS-specific. The second machine's OS is a decision input [U]. |

**Risk observed [V]:** that live Codex automation's prompt says *"merge only if the required conditions are met"* and refers to *"the user's conditional merge authorization"*. That is a pre-authorized, conditional merge into `main`, carried out by a scheduled agent. It conflicts with CLAUDE.md's "explicit confirmation before merge", which is never automatic. A Manager that schedules resumes needs a hard rule that no wake prompt may carry merge authority. See R3.

---

## 3. Fit with A39 and the existing contracts

**Where the Manager sits.** A39 has one canonical policy, two runtime mappings, and no adapter-specific policy override. So:

- **Manager policy** goes in a canonical skill (`skills/<manager>/SKILL.md`, name to be chosen). It is consumed by whichever runtime hosts the Manager. Claude hosts it in v1 because the vision says so. It must **not** go into the SessionStart injection: `ORCHESTRATOR.md` is already 13,933 bytes against Claude's 10,000-character hook cap (#499 is open). The Manager loads its skill explicitly when started as a Manager.
- **Runtime Session Adapter** is a new deep Module with a small Interface: `start(clone, brief, model) → handle`, `status(handle) → working | needs-human(question) | done(report) | limited(resets_at|unknown) | failed(reason)`, `resume(handle, message)`, `identity(handle) → #503 record`. Behind it sit `claude --bg/--resume/agents --json/jobs state` and `codex exec/exec resume/rollout parse/</dev/null`. **Real Seam, two adapters:** Claude and Codex genuinely differ in every operation listed. Deletion test: without this Module, every Manager rule would have to spell out CLI flags, stdin quirks, rollout paths and state vocabularies twice, so the complexity would reappear in the callers. The Module earns its Depth.
- **Limit Ledger** is a read-only Module: `limits() → [{runtime, window: 5h|7d, used_pct|unknown, resets_at|unknown, observed_at, source}]`. Its two readers are real (Codex rollout and Claude transcript/statusline). One normalized record, which also supports the deletion test.
- **Wake** is one Interface (`schedule_wake(at, resume_command)`, `cancel`), with **one** adapter in v1 (launchd). A Linux adapter is **hypothetical** until a second machine needs it, so per the two-adapters rule, do not introduce the Seam yet. Write the launchd code behind a plain function.

**Hypothetical Seams to refuse now:**
- A separate Codex CLI adapter and Codex Desktop adapter. They share the installation (A39) and the rollout format [V]. The Manager can only *start* CLI sessions, and only *observes* desktop ones.
- A Manager-level per-role dispatcher that mixes runtimes inside one work item. It is possible: #489 has Codex Implementation/Test/Review and Claude Planning/Review markers on one PR [V]. But it would duplicate ORCHESTRATOR dispatch at a second level. Defer it until a work item actually needs it, and keep it as an open decision.
- A generic "agent framework" or plugin. A39 already says "no speculative CLI/desktop/plugin Module or dispatch framework".

**Contract touch points (no edits proposed here, only flagged):**
- ORCHESTRATOR "**Cannot dispatch** → stop and ask" and A39 "unavailable fresh role dispatch stops that stage". A limit hit is a third case: *paused, resumable*. It is neither an override nor a collapse. This needs one sentence of canonical policy: "limited ≠ unavailable: pause, record the reset in the Pipeline log, resume at the same stage; never switch the remaining stages to the other runtime without a decision-by-rule row or human decision".
- ORCHESTRATOR "**Resume**: read durable artifacts" is exactly what makes a woken Manager safe. The Manager should hold no state that is not in issue/PR artifacts or a ledger file. Its own transcript is a convenience, not a source of truth.
- Fresh Reviewer (A27). If the Manager resumes a work-item orchestrator, nothing changes. The Manager must never `resume` a role session that was a Reviewer. That is ORCHESTRATOR's existing rule, enforced in the adapter by refusing to resume a handle tagged `Review`.
- **Human decision authorship** (A10, #415, #503 "human decision/override authorship"). A relayed answer becomes a numbered human decision that quotes the maintainer verbatim, recorded with "relayed by Manager session <id>". The same applies to merge confirmation into `main`: it must name the PR and head SHA. Whether a relayed confirmation counts at all is a maintainer decision (D1).

**Isolation per clone [V].** `adopt.sh:516` refuses a project whose `.git` is not a directory. `lib/codex-adoption.py:87` and `lib/claude-status.py:42` do the same. A linked worktree has a `.git` *file*, so `codex exec --worktree` [H] and Claude's `EnterWorktree` are unusable for an adopted project as things stand. The existing practice is full clones per work item: `/private/tmp/sdg-419`, `sdg-441`, `sdg-455-cli-live`, `sdg-455-claude-live` [V]. `/private/tmp/sdg-455` is a worktree [V] and so could not be adopted. The Manager provisions a clone per work item. One clone per work item also means no shared checkout, which fits A11's one-branch-per-work-item rule.

**Workflow source pickup [V].** `SPEC_DRIVEN_GUARDRAILS_DIR` (Claude) and `.guardrails/source` (Codex) point at one SDG checkout, and Claude's WORKFLOW symlink "follows live" (A39). When the Manager develops **SDG itself**, the workflow *source* must be a separate, pinned clone, not the clone being edited. Otherwise a branch switch in a dev clone silently changes the rules of every adopted project on the machine. #503 already requires the workflow-source SHA in each observation, and the Manager can record it at `start`.

**Concurrency: what is still shared even with separate clones.**
- Account limits. All Codex sessions draw on one 5h/weekly window, and all Claude sessions on another. Running in parallel spends the budget faster; it does not add budget.
- GitHub state: labels, the one Pipeline-log comment per issue.
- `~/.claude` and `~/.codex` global state, and `gh` auth.

The Manager needs a **lease** per work item: one live session per issue, recorded as the owning session id in the Pipeline log plus `status:in-progress`, so two sessions never take the same issue.

---

## 4. Capability-based assignment: evidence versus lore

**Evidence that exists [V]:**
- `model-record` markers, per stage per PR. For example #489 has `gpt-6.1-sol` for Implementation ×5, Test ×5, Review ×5 and Planning ×2, and `claude-opus-5-5` for Review ×3, Planning ×1 and Test ×1. #508 is all `gpt-6.1-sol`. #493 and #495 have `claude-sonnet-5-5` Implementation and `claude-opus-5-5` Review.
- Pipeline logs with model per dispatch and a one-line "Decided by rule" rationale for each model choice (#419, #453).
- `review-rounds.sh`: rounds and Architect resets per PR (#489: 5 rounds, 3 planning-after).
- Findings with slug, class, severity and verdict, which `finding-carryforward-gate.sh` parses already.
- CI durations.
- Tokens per Claude job and per Codex turn/thread.
- #503 observations, which are runtime-specific defects.

**Lore:** "Codex is stronger at X, Claude at Y". There is no attributed record of it in the repo. Sample sizes per (model, stage) are small: a handful of PRs.

**Proposal: derive the record, do not hand-keep a table.** Add a read-only `capability-evidence.sh` in the family of `compliance-evidence.sh` (A15 Interface: run by path, read-only, never writes). For each (runtime, model, stage) it reports:
- n, the number of stages carried;
- findings later raised *against that stage's output*, by class and severity. A `code` finding is attributed to the Implementation model and a `test` finding to the Test model. When a stage had several models, the finding is marked "unattributable" instead of guessed.
- Review rounds to approve and loop-backs triggered;
- observed tokens or limit-percent cost where available;
- #503 defects per runtime.

It always prints n and never prints a rank. A39 already excludes an evidence "ranking table". The Manager *reads* this as input to an assignment that is either a logged decision-by-rule (cheapest runtime/model clearing the floor, per `model-choice`) or a question to the human. The cross-vendor Review floor ("at least as capable as Implementation") has no machine ordering across vendors. It stays a recorded `floor-basis` judgment, and the Manager must not automate it.

**Limit-aware admission.** Before starting a stage, compare the ledger's remaining window with a cost estimate for that stage. The estimate is the median tokens of past stages of that kind, taken from Pipeline logs, job `tokens` and Codex `token_usage_record`. The token-to-percent rate for Codex can be learned from consecutive `token_count` records (Δtokens versus Δused_percent), but it is approximate [U]. The rule stays simple: do not start a stage you are likely unable to finish in the current window. Starting it would leave a half-done role that has to be resumed, which costs re-reading.

---

## 5. Risks

| # | Risk | Severity | Mitigation |
| --- | --- | --- | --- |
| R1 | The Manager runs on Claude, so a Claude limit stops the Manager itself. In-session cron dies with it. | high | Wake comes from an OS one-shot that starts a fresh Manager, which resumes from artifacts and the ledger only |
| R2 | Claude's limit signal is human text plus statusline-only percentages. Parsing drift could cause early or late wakes. | medium | Fail closed (unknown reset → wake at the next 5h boundary plus a margin, then re-check). Fixture tests on sanitized strings. |
| R3 | Wake or resume prompts that carry merge authority (observed live in a Codex automation) | high | Canonical rule: wake prompts never authorize a merge into `main`. The merge guard already blocks without CI. Add an adapter check that refuses a brief containing merge authority. Maintainer decision D1. |
| R4 | Relayed answers blur authorship ("the human said" written by an agent) | high | Verbatim quote, decision number, and Manager session id. Merge confirmation names the PR and SHA. #503 records it as a relayed observation. |
| R5 | Dev clone used as workflow source (SDG self-development) | high | A pinned source clone, recorded as the source SHA at `start` |
| R6 | Parallel sessions spend a shared window faster, and all stall at once | medium | Admission control from the ledger. Concurrency cap of one per runtime by default, as a decision. |
| R7 | `codex exec` hangs on stdin. Exit 1 hides the cause (limit, overload or auth). | medium | The adapter always redirects stdin and classifies from the rollout `codex_error_info` |
| R8 | Context budget: Manager rules pushed into SessionStart worsen #499 | medium | The Manager skill is loaded explicitly, never injected |
| R9 | Capability record over-read from n≈5 | medium | Always print n. No ranking. The human or a decision-by-rule decides. |
| R10 | Codex rollout format is undocumented and private (fields like `rate_limit_reached_type`, `thread_spawn`) and may change between versions | medium | Version-tag the reader. An unreadable field returns `unknown`, never zero (the same stance as A26). |
| R11 | Linked worktrees refused by adoption, so clones cost disk and time | low | Accept full clones. Revisit only if adoption learns worktrees (a separate decision). |

---

## 6. Candidate decomposition (rough effort; S ≈ ≤1 day, M ≈ 2–3 days, L ≈ 4+ days, each through the five-role pipeline)

1. **W0 Spike (live, S, blocked until the Codex reset at 18:34 today).** Confirm the [U] items:
   - the success-path `codex exec --json` events, and whether they include `rate_limits`;
   - `codex exec resume` after a reset;
   - `codex queue` to an exec thread;
   - `claude --bg --resume` behavior after a limit hit;
   - `--brief`/`SendUserMessage` in `--bg`;
   - whether statusline input carries reset times.

   The output is a #503-style observation record, so it doubles as #503 evidence.
2. **W1 Spec and decisions (Product + Architect, S).** The Manager's scope, the two-level shape, relay authorship, the "limited ≠ unavailable" sentence, the no-merge-in-wake rule, and an ARCHITECTURE entry (A40) recording the Modules and Seams above.
3. **W2 Runtime Session Adapter (M–L).** Claude and Codex adapters behind start/status/resume/identity. Tests use fake `claude`/`codex` executables on PATH as the Seam, plus sanitized rollout and `state.json` fixtures.
4. **W3 Limit Ledger (M).** A Codex rollout reader and a Claude transcript reader, with an optional statusline-tee reader if D3 says yes. Normalized output. Fail-closed tests.
5. **W4 Wake (M).** launchd one-shot write and cancel. The resume command starts a fresh Manager from artifacts. Exactly one pending wake per Manager.
6. **W5 Decision relay protocol (S–M).** A "Decision needed" artifact format the orchestrators post, batched collection by the Manager (A10), and the recorded numbered human decision with relay attribution. Mostly skill text, plus the detection inside W2's `status`.
7. **W6 Clone provisioning and lease (M).** A clone per work item, adoption against the pinned source, the lease in the Pipeline log and `status:in-progress`, and cleanup.
8. **W7 `capability-evidence.sh` (M).** Read-only, reusing `lib/model-record.sh`, `lib/review-rounds.sh` and the carry-forward finding parser.
9. **W8 Manager skill and adapter mapping lines (S).** The canonical policy text, regenerated through `generate-workflow-adapters.sh`. No adapter policy.
10. **W9 Live dry runs (ongoing, feeds #503).**

Order: W0 → W1 → (W3, W2) → W5 → W6 → W4 → W8, then W7 whenever the evidence is wanted. The minimal useful slice is W0 + W1 + W2 (Codex only) + W3 (Codex only) + W5. That slice is "Claude Manager drives Codex work items, relays questions, pauses on Codex limits", roughly 1.5–2 weeks. Claude-side wake (W4) is what makes the Manager survive its own limit, and it is the riskiest part.

## 7. Decisions for the maintainer (batched, A10)

- **D1.** May a merge confirmation into `main` be relayed through the Manager, verbatim and naming the PR and SHA? Or must it always be typed in the work-item session or on the PR? And should "no merge authority in any wake/scheduled prompt" become canonical, which would retire today's conditional-merge Codex automation?
- **D2.** Two-level, where the Manager manages per-work-item orchestrators (recommended), or flat, where the Manager dispatches individual roles across runtimes?
- **D3.** May the user-level statusline command be changed to also write its input JSON to a file, so the Manager gets Claude's 5h/7d percentages before a hit?
- **D4.** The second machine's OS, which decides whether a non-launchd Wake adapter is ever real. Also the default concurrency cap per runtime.
- **D5.** Is SDG self-development by the Manager in scope for v1, or adopted projects only? Self-development needs the pinned-source rule (R5) on day one.
