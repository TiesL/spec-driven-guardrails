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

**Dispatch:** start every role as a new agent, never the dispatch tool's `fork` type (a fork inherits your whole context, which breaks the role's scoped input). Start every dispatch prompt with `ROLE SESSION: <role>`, quote that role's contract from the `role-contracts` skill, name its scoped input (A8). Each role posts its own report with its own `model-record` marker. Dispatched roles never merge. A merge into `main` always waits for the human; merging a work-item PR into a release branch is your step and follows the `release-branch-workflow` skill (WORKFLOW.md says when). Every Review round is a new dispatch of a fresh Reviewer, and a Reviewer is never continued: never `SendMessage` to an earlier round's Reviewer, and never the dispatch tool's `fork` type (that is the tool's agent type, not the `context: fork` of `pre-merge-review`). Whether another role, once started, may be continued for a later step is not decided here (#412).

**Review round brief.** Build every Review round's brief from artifacts only: the PR number, its head SHA and the diff command, the work-item issue, a link to the previous round's findings comment with its open `finding:` slugs, and the `finding-carryforward-gate.sh` command. Fix commits and the Developer's comments are artifacts and may be linked. The brief never includes the earlier Reviewer's conversation, a summary of it, or your paraphrase of its findings: carried-forward findings are inputs the new Reviewer re-checks against the new head, not memory.

**Loop-back (A28).** Route every finding by its class, to the role that owns the fix, whichever stage found it (roles in order):

| Class | Route |
| --- | --- |
| `design` | Architect, QA, Developer, fresh Reviewer |
| `code` | QA (a red test for the defect), Developer, fresh Reviewer |
| `test` | QA, Developer, fresh Reviewer |
| `spec` | Product, then the Architect if the design is affected, QA, Developer, fresh Reviewer |

Never relay a Reviewer's suggested fix as a decision; the next role's brief links the findings. You never downgrade a class. When a finding has no class, or you doubt a design class, dispatch the Architect, who may record that it is not a design defect and route it as code.

**Any stage.** A Developer or QA that finds a design defect stops the change, saves the attempted patch (A12) and reports the finding with class `design`; you route it like any other finding.

**Two-round trigger.** A Review round counts when it reports at least one open finding of severity medium or high, new or carried over. When two consecutive rounds on one PR count, dispatch the Architect for a redesign step before any Developer fix. The Architect records that step as a PR comment with a Planning marker, and may conclude that no design change is needed. The count starts again after that recorded Architect step.

**Override.** If the maintainer tells you to patch a design defect in code instead of looping it back, that waives the loop-back route, so the A29 (#415) flow applies: the Architect pushes back once, the decision is a numbered human decision naming the rule overridden (the loop-back route, A28) and linking the pushback, and the Architect writes the risk note. The pushback and the risk note are defined in #415 (A29); this file defines no format and no marker for them.

**Pipeline log.** Keep one comment per work-item issue, headed "Pipeline log", that you write and edit. It never carries a `model-record` marker. Write one line per dispatch when you dispatch: the stage, the round (for Review), the agent id the dispatch tool returned, and the model requested.

**Before asking for a merge,** run this self-check and record its result as a line in the issue's Pipeline log: every Review round in the pipeline log has its own agent id, and no message went to an earlier Reviewer. GitHub artifacts cannot show whether two rounds came from different agent instances, so this check is a recorded self-check, not a pass. The same self-check also records:

- No design-class finding was fixed without an Architect step before the fix commit.
- The two-round trigger did not fire, or its Architect step is on the PR (count the rounds with `$SPEC_DRIVEN_GUARDRAILS_DIR/review-rounds.sh <pr> [<issue>]`, run with the project's checkout as the working directory; run inside the guardrails repo it would count that repo's PR with the same number).

Limit: class and severity are judgments. A script can only check that the route left evidence.

**Model per stage.** Before each dispatch, assess that stage's floor on its own demands, per the `model-choice` skill: what would a model that is too weak get wrong here? Then choose the cheapest model that clears it, separately for each stage, never one model for the whole run. Review must be at least as capable as Implementation's recorded model. A different model is not required. Choose the model when you dispatch. The dispatch tool takes no effort argument, so effort is neither chosen nor recorded in markers, and the same model at a lower effort meets the floor, an accepted risk (see "The limit" in the `model-choice` skill). Name the chosen model in the dispatch prompt, and hand the role its marker line as the next paragraph says.

**Marker line: never typed.** Nobody types a `model-record` marker by hand: it is produced by `model-record-emit.sh`, and its format is owned by the `model-choice` skill ("Machine-readable form"). Resolve the command's absolute path once: `$SPEC_DRIVEN_GUARDRAILS_DIR/skills/pre-merge-review/model-record-emit.sh`, or, if that variable is unset, the project's `.claude/skills/pre-merge-review/model-record-emit.sh` resolved with `pwd -P`. In each dispatch prompt, give the role that command with `--stage` filled in, and name the model you requested. The role adds `--model` with its own exact model id (the Reviewer also adds `--floor-basis` with its one sentence, quoted for the shell) and pastes the command's output, unchanged, as the first line of its report.

**No self-granted shortcuts.** Never skip, shorten or merge stages on your own judgment, not even for a change you consider trivial. Only the human can override. When the human explicitly says to run the work item as a single session, or to skip a stage, comply and post this record on the issue, as live text (not in a code block or quote), quoting their instruction:

`<!-- pipeline-override: decided-by="human" scope="single-session" reason="<the human's words>" -->`

`scope` is `single-session` or `skip=<Stage>` (one of the five stages above); `decided-by` and `reason` must not be empty. Without a valid record, the merge guard refuses `gh pr merge` on a run where one text carries markers for several stages or a stage is missing (`model-record-gate.sh` prints a `role-played:` line).

**Cannot dispatch** (no agent tool in this environment, or dispatch fails): stop and ask the human whether to override as above or to stop. Never silently play the roles yourself.

**Resume:** on an existing work-item branch, find the stages already evidenced (their `model-record` markers and the issue's role label; `$SPEC_DRIVEN_GUARDRAILS_DIR/role-label-staleness.sh <issue>`, run with the project's checkout as the working directory so it reads the project's repository, reports the latest one) and resume at the first stage without a marker. Do not restart, and do not skip ahead.
