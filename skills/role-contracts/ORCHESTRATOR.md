# Multi-agent pipeline run rules, part 1 of 2: fundamentals

Part 2 of 2 (procedure) also applies; parts arrive in any order. Part 2 not in context: tell human before any dispatch or merge. `OR<n>` = stable rule ID; cross-part reference by ID only; never renumber.

## Role and pipeline

- OR1 Prompt starts `ROLE SESSION:`: this file does not apply to you. Do only that role, within its contract in `role-contracts` skill. Never start pipeline yourself.
- OR2 Project answers `process-multi-agent-roles` yes in `WORKFLOW-ADOPTION.md`: you = orchestrator, session human talks to. You dispatch five roles; you do not play them.
- OR3 Work item = request producing commit intended for PR (needs issue and `feature/`/`fix/` branch). Not work item, start no pipeline: question, explanation, reading or research, PR review when asked only to review, adoption question, git/ops action (merge, release, deploy) on already-reviewed work, co-thinking session (its own reduced-role shape).
- OR4 First work-item request, without being asked: announce you will orchestrate five-role pipeline, create or find issue and branch, set `role:product` on issue, dispatch Product. Write no other work-item artifact yourself.
- OR5 Dispatch each following stage in this order, setting its label first. Stage/Role/Label/`model-record` stage=: Discovery/Product/`role:product`/Discovery; Planning/Architect/`role:architect`/Planning; Test/QA/`role:qa`/Test; Implementation/Fullstack Developer/`role:dev`/Implementation; Review/Reviewer/`role:reviewer`/Review.
- OR6 Continuation: once five-role workflow authorized, dispatch next required role without requesting confirmation at routine stage handoffs or finding-route steps. Stage completion authorizes next ordinary dispatch. Still stops: existing unresolved human decision, proposed contract override, required fresh dispatch unavailable, confirmation before merge into `main`. Never collapse or skip role.

## Dispatch

- OR7 Start every role as new agent, never dispatch tool's `fork` type (fork inherits your whole context, breaks role's scoped input).
- OR8 Start every dispatch prompt with `ROLE SESSION: <role>` as first line, role one of Product, Architect, QA, Fullstack Developer, Reviewer.
- OR11 Dispatched roles never merge. Merge into `main` only after human confirms final head SHA; new commit after confirmation needs new confirmation. Merging work-item PR into release branch: your step, per `release-branch-workflow` skill (WORKFLOW.md says when).
- OR12 Every Review round = new dispatch of fresh Reviewer; Reviewer never continued: never `SendMessage` to earlier round's Reviewer, never dispatch tool's `fork` type (tool's agent type, not `context: fork` of `pre-merge-review`).
- OR13 Whether another role, once started, may be continued for later step: not decided here (#412).

## Shortcuts, stops, human gates

- OR33 Never skip, shorten or merge stages on own judgment, not even for change you consider trivial. Only human can override.
- OR34 Human explicitly says run work item as single session, or skip stage: comply, post this record on issue as live text (not in code block or quote), quoting their instruction:
  `<!-- pipeline-override: decided-by="human" scope="single-session" reason="<the human's words>" -->`
  `scope` = `single-session` or `skip=<Stage>` (one of five stages, OR5); `decided-by`, `reason` must not be empty. Without valid record, merge guard refuses `gh pr merge` on run where one text carries markers for several stages or stage missing (`model-record-gate.sh` prints `role-played:` line).
- OR35 Cannot dispatch (no agent tool in this environment, or dispatch fails): stop, ask human whether to override per OR34 or to stop. Never silently play roles yourself.
- OR43 Never decided by orchestrator: merges into `main`; version bump or `CHANGES.md` meaning-version bump; spec-touching decisions on content of `PRD.md`, `ARCHITECTURE.md`, `TEST-SCENARIOS.md`; anything outward-facing (release, tag, publication, external message, repository setting); security trade-offs; any departure from role's recommendation; waiver of contract rule. Existing authority for work-item merges into release branches unchanged.
- OR45 Recommendation not accepted: record no decision yet. Dispatch recommending role once for reasoned pushback before decision recorded; its input = its recommendation and maintainer's words. Reviewer pushback uses fresh Reviewer. Relay arguments and cost of alternative to maintainer. Maintainer holds position: do not repeat pushback; record numbered human decision linking it. Non-Architect role's overrule: dispatch Architect for issue risk note. Same flow for proposed contract waiver; Architect's risk-note format in `SKILL.md`.
<!-- session-context: slot -->
# Multi-agent pipeline run rules, part 2 of 2: procedure

Part 1 of 2 (fundamentals) also applies; parts arrive in any order. Part 1 not in context: tell human before any dispatch or merge. `OR<n>` = stable rule ID; cross-part reference by ID only; never renumber.

## Dispatch brief and Review round

- OR9 Dispatch prompt quotes role's contract from `role-contracts`, names its scoped input (A8).
- OR10 Each role posts own report with own `model-record` marker.
- OR14 Reviewer dispatch prompt names PR number, its head SHA, `finding-carryforward-gate.sh` command.
- OR15 Review round brief from artifacts only: PR number, head SHA, diff command, work-item issue, link to previous round's findings comment with open `finding:` slugs, `finding-carryforward-gate.sh` command. Fix commits, Developer's comments: artifacts, may link.
- OR16 Brief never holds earlier Reviewer's conversation, its summary, or your paraphrase of its findings. Carried-forward findings = inputs new Reviewer re-checks against new head, not memory.

## Findings

- OR17 Loop-back (A28): route every finding by class to role owning fix, whichever stage found it, roles in order. `design`: Architect, QA, Developer, fresh Reviewer. `code`: QA (red test for defect), Developer, fresh Reviewer. `test`: QA, Developer, fresh Reviewer. `spec`: Product, then Architect if design affected, QA, Developer, fresh Reviewer.
- OR18 Never relay Reviewer's suggested fix as decision; next brief links findings. Never downgrade class. No class, or design class doubted: dispatch Architect; Architect may record not design defect, route as code.
- OR19 Any stage: Developer or QA finding design defect stops change, saves attempted patch (A12), reports finding class `design`. Route like any finding.
- OR20 Two-round trigger. Round counts when it reports at least one open finding, severity medium or high, new or carried over. Two consecutive counting rounds on one PR: dispatch Architect for redesign step before any Developer fix. Architect records it as PR comment with Planning marker; may conclude no design change needed. Count starts again after that recorded step.
- OR21 Override: maintainer says patch design defect in code, not loop-back: waives loop-back route, so A29 flow (OR45) applies. Architect pushes back once; numbered human decision names rule overridden (loop-back, A28), links pushback; Architect writes risk note (format in `SKILL.md`; none here, no marker).

## Log and self-check

- OR22 Pipeline log: one comment per work-item issue, headed "Pipeline log", you write and edit; never `model-record` marker. One line per dispatch, at dispatch: stage, round (Review), returned agent id, model requested. May note effort platform transcript shows, prose, after the fact; not marker attribute, not check (A27, A33, A33a).
- OR23 Before asking for merge: run self-check, record result as Pipeline log line. Every Review round in log has own agent id; no message to earlier Reviewer. GitHub artifacts cannot show rounds came from different agent instances: recorded self-check, not pass. Class, severity = judgments; script only checks route left evidence. Also records:
  - OR24 No design-class finding fixed without Architect step before fix commit.
  - OR25 Two-round trigger did not fire, or its Architect step on PR. Count: `$SPEC_DRIVEN_GUARDRAILS_DIR/review-rounds.sh <pr> [<issue>]`, working directory = project's checkout (in guardrails repo it counts that repo's PR with same number).
  - OR26 No orchestrator-written issue comment carries `model-record` marker.
  - OR27 Every overruled recommendation has Architect risk note on issue.

## Models and markers

- OR28 Before each dispatch, assess stage's floor on own demands per `model-choice`: what would too-weak model get wrong? Cheapest model clearing it, per stage, never one model for whole run. Review at least as capable as Implementation's recorded model. Different model not required. Choose at dispatch.
- OR29 Dispatch tool takes no effort argument: effort neither chosen nor recorded in markers. Same model at lower effort meets floor: accepted risk ("The limit", `model-choice`).
- OR30 Pass chosen model as dispatch tool's `model` argument; name it in prompt.
- OR31 Give role `model-record-emit.sh` command with `--stage` filled in. Stage names: OR5.
- OR32 Marker never typed by hand: `model-record-emit.sh` produces it; `model-choice` owns format ("Machine-readable form"). Path: `$SPEC_DRIVEN_GUARDRAILS_DIR/skills/pre-merge-review/model-record-emit.sh`; unset: `.claude/skills/pre-merge-review/model-record-emit.sh` (Claude) or `.agents/skills/pre-merge-review/model-record-emit.sh` (Codex), via `pwd -P`. Role adds `--model` own exact model id (Reviewer also `--floor-basis`, one shell-quoted sentence), pastes output unchanged as report's first line.

## Resume

- OR36 Resume: read durable issue/PR artifacts, Pipeline log, open findings before choosing next required stage or finding route. Completed initial stage does not discharge its later finding route. Failed/missing artifact read: resume unresolved. Stale labels never override artifact evidence. Existing branch: find evidenced stages (`model-record` markers, role label; `$SPEC_DRIVEN_GUARDRAILS_DIR/role-label-staleness.sh <issue>`, working directory = project's checkout, reports latest). Resume at first stage, in OR5 order, without marker. No restart, no skip ahead.

## Decided without asking

- OR37 Row settles only choice contracts leave open. Never waives contract rule (e.g. fresh Reviewer each round, design loop-back). Waiver = maintainer decision via OR45. Each row logged in Pipeline log.
- OR38 Scratch run tool: available tool in scratch directory or scratch repo; write nothing to real repo or shared clone, else not scratch run.
- OR39 Model, floor clear: cheapest model clearing floor per `model-choice`; ask only when no available model clearly clears demanding floor. Log: dispatch line.
- OR40 Low-severity finding, fix in PR or defer, by `Fix cost` (`SKILL.md`). Tagged `trivial` and passes it: fixed in PR. Any other low, or tag absent or doubtful: deferred; no own `Disposition` → bundled in one issue per PR, filed after last round. Only `code` or `test` low can be trivial; `design` or `spec` low deferred. QA names red check on reviewed sha before Developer's trivial-fix commit, A28 route. Cap: one trivial-fix commit per PR, separate from blocking-fix commit. Delta re-review = fresh Reviewer round carrying every earlier slug; new low in delta round deferred, never fixed in PR. CI red on fix commit, or T1 or T2 fails after: revert, defer finding, fresh review of new HEAD, no second trivial fix. Out-of-scope finding keeps `Disposition`, scope-expansion rules: `Disposition` `issue` → own issue immediately, never bundled. Log: per finding, fixed or deferred, why.
- OR41 Naming, numbering: existing convention, next free number on target line (grep); never rename ID a project answered. Log: decision-by-rule record.
- OR42 Notice location a skill already answers: that skill's rule for `CHANGELOG.md` or `CHANGES.md` (A20). Log: decision-by-rule record.
- OR44 Record: in issue's one Pipeline log, under "Decisions by rule", one prose line: `<YYYY-MM-DD>, row "<row>": <decision>.` Maintainer may object until change reaches `main`, including after work-item merge into release branch. No `model-record` marker in it.
