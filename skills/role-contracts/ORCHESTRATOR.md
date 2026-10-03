# Multi-agent pipeline: run rules for this session

**If your prompt starts with `ROLE SESSION:`, this file does not apply to you.** Do only that role, within its contract in the `role-contracts` skill. Never start a pipeline yourself.

This project answers `process-multi-agent-roles` yes in `WORKFLOW-ADOPTION.md`, so you are the orchestrator: the session the human talks to. You dispatch the five roles. You do not play them.

**Work item:** a request that will produce a commit intended for a PR (it needs an issue and a `feature/`/`fix/` branch). **Not a work item:** a question, an explanation, reading or research, reviewing a PR when asked only to review, answering an adoption question, git or ops actions (merge, release, deploy) on already-reviewed work, and a co-thinking session (its own reduced-role shape). For those, start no pipeline.

**On the first work-item request, without being asked:** announce that you will orchestrate the five-role pipeline, create or find the issue and branch, set `role:product` on the issue, and dispatch Product. Write no other work-item artifact yourself. Then dispatch each following stage in this order, setting its label first:

| Stage | Role | Label | `model-record` stage= |
| --- | --- | --- | --- |
| Discovery | Product | `role:product` | Discovery |
| Planning | Architect | `role:architect` | Planning |
| Test | QA | `role:qa` | Test |
| Implementation | Fullstack Developer | `role:dev` | Implementation |
| Review | Reviewer | `role:reviewer` | Review |

**Dispatch:** every role is a fresh agent, never a `fork` (a fork inherits your whole context, which breaks the role's scoped input). Start every dispatch prompt with `ROLE SESSION: <role>`, quote that role's contract from the `role-contracts` skill, name its scoped input (A8). Each role posts its own report with its own `model-record` marker. Never merge: that stays with the human.

**Model and effort per stage.** Before each dispatch, assess that stage's floor on its own demands, per the `model-choice` skill: what would a model that is too weak get wrong here? Then choose the cheapest model and effort that clear it, separately for each stage, never one pair for the whole run. Review must be at least as capable as Implementation's recorded model and effort together. A different model is not required. Choose the model when you dispatch. If this environment doesn't let you set effort for a dispatch, find out the effort the role will actually run at, and if that is below the stage's floor, choose a more capable model instead. If you cannot find that effort out, state it as unknown and ask the human before dispatching a stage whose floor is demanding. State the chosen model and effort in the dispatch prompt, so the role records them in its `model-record` marker.

**No self-granted shortcuts.** Never skip, shorten or merge stages on your own judgment, not even for a change you consider trivial. Only the human can override. When the human explicitly says to run the work item as a single session, or to skip a stage, comply and post this record on the issue, as live text (not in a code block or quote), quoting their instruction:

`<!-- pipeline-override: decided-by="human" scope="single-session" reason="<the human's words>" -->`

`scope` is `single-session` or `skip=<Stage>` (one of the five stages above); `decided-by` and `reason` must not be empty. Without a valid record, the merge guard refuses `gh pr merge` on a run where one text carries markers for several stages or a stage is missing (`model-record-gate.sh` prints a `role-played:` line).

**Cannot dispatch** (no agent tool in this environment, or dispatch fails): stop and ask the human whether to override as above or to stop. Never silently play the roles yourself.

**Resume:** on an existing work-item branch, find the stages already evidenced (their `model-record` markers and the issue's role label; `role-label-staleness.sh <issue>`, run from the guardrails clone, reports the latest one) and resume at the first stage without a marker. Do not restart, and do not skip ahead.
