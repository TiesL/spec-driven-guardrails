# Method — Git/GitHub Workflow

This project is developed from multiple computers. Follow this workflow in every session, regardless of which machine you're working on. This text is symlinked as `CLAUDE.md` in adopted projects — see `README.md` in this repo for the adoption procedure.

## Branch strategy: GitHub Flow

- `main` is always stable/working. **Never commit or push directly to `main`** — this is a workflow agreement, not a technically enforced rule (GitHub branch protection on private repos requires a paid plan).
- All work happens on a short-lived branch from the current `main`, named after the issue it implements:
  - `feature/<issue-number>-<kebab-case-description>` for new functionality/epics
  - `fix/<issue-number>-<kebab-case-description>` for bug fixes (including trivial ones, such as documentation corrections)
- For an epic spanning several work items, an optional **release branch** (`release/<epic-number>-<slug>`) can sit between work-item branches and `main` — see the `release-branch-workflow` skill for when to use one, who may merge what into it, and how its own merge into `main` is confirmed differently than a work item's merge into it.
- **No request leads straight to development.** What's being built is specified in an issue first — see the `write-spec` skill for the epic/work-item templates. The branch name can't even be written without that issue's number. **This includes editing a tracked file at all, even a draft you plan to show before committing** — `git-guardrails`/the native `pre-commit` hook enforce the branch-naming and commit-on-main parts of this mechanically, but neither one sees an `Edit`/`Write` tool call (only `Bash`), so nothing mechanical stops the file itself from being changed before the issue and branch exist. "I'll draft it on `main` and ask before committing" is exactly the violation this rule rules out, not an exception to it — create the issue and branch first, then edit.

## When starting a session

1. `git fetch origin` (also happens automatically via a `SessionStart` hook, see `settings/session-hooks.json`). The same hook prints what this project opted into that must be in every session's context (`session-context.sh`), such as the multi-agent run rules; when it does, those rules apply to this session.
2. Check whether you're continuing existing work (existing feature branch) or starting something new.
   - Existing work: `git checkout <branch> && git pull origin <branch>`.
   - New work: create the issue first — `gh issue create` with the epic or work-item template (`templates/ISSUE_TEMPLATE/`, see `write-spec`) — then branch from its number: `git checkout main && git pull origin main && git checkout -b feature/<issue-number>-<name>` (or `fix/<issue-number>-<name>`).
3. Review recent history for context: `git log --oneline -10` — especially useful if you're continuing on the other computer and want to see what's happened since last time.

## During the work

- Commit logical steps on the feature branch.
- Push regularly to `origin/<branch>` — never to `main`. This also happens automatically: a `SessionEnd` hook pushes the current branch when a session ends, with a guard that skips this when `main` happens to be checked out (extra safety net, since there's no branch protection — see below).
- Commit messages carry no "Co-Authored-By" trailer — enforced via `attribution.commit: ""` in `settings/session-hooks.json`, not dependent on whether the executing session remembers to do so.

## Wrapping up

**Confirmation is required only before merge (step 4 below).** Committing, pushing, opening a PR, and running the review all proceed without asking — do not invent an extra approval checkpoint at any of those points, even right after being corrected on a different mistake. If something about the change is genuinely unclear, ask that specific question directly instead of adding a generic "approve to proceed?" gate.

**This confirmation requirement is for a merge into `main`.** A work-item PR targeting a release branch instead follows the `release-branch-workflow` skill's own lower-ceremony path — merge on CI-green + tests-pass, no separate confirmation per work item. Steps 1-5 below describe the `main`-bound case; a release branch's own eventual merge into `main` still needs the maintainer's explicit confirmation, same as any other merge into `main`.

1. Once the change is complete and tested (and, where applicable, manually verified): open a PR with `gh pr create`. If the PR refers to an issue (`Closes #N`), put that link in the **PR description itself**, not only in a commit message: GitHub populates `closingIssuesReferences` — the field that issue-linking checks actually test against — exclusively from the PR title/body. A commit with `Closes #N` does close the issue on a merge to `main`, but such a check won't see the link while the PR is still open.
2. **Run the quality review immediately, in parallel with CI, not gated on CI being green** — don't ask whether to, don't wait to be asked, don't wait for CI first; see the `pre-merge-review` skill. The review's marker is pinned to the commit it reviewed, so a commit that lands afterward (a fixup, or a fix for a red CI) simply needs a fresh review, whenever it runs — nothing slips through unreviewed.
3. Before asking for merge confirmation, know that CI has actually finished — the merge guard blocks the merge otherwise, and asking prematurely just costs a round trip. Don't poll `gh pr checks` on a short fixed interval — measured against this repo's own last 10 completed CI runs (`gh run list --json createdAt,updatedAt`), durations cluster at 5.5-8 minutes (one outlier at ~23min), so a 20s interval produces a dozen-plus "still pending" checks before CI ever finishes (issue #215). Run `./wait-for-ci.sh <pr-number>` instead of polling by hand (issue #265) — it waits 5 minutes before the first check, then every 1 minute until CI reaches a terminal state, and exits non-zero if anything failed. That interval is a documented agreement precisely so an agent can't quietly improvise a shorter one; encoding it in a script closes that gap the same way a prose-only rule can't.
4. **Wait for TiesL's explicit confirmation** that the test succeeded and there's no regression, before merging. Never merge automatically without that confirmation.
5. Then merge with `gh pr merge --squash --delete-branch` — this keeps the history on `main` clean and cleans up the branch (local and remote) immediately.

## Issue labels

Three independent axes, applied to every issue going forward (issue #398 — before this, the tracker carried almost no labels at all, making two concurrent sessions' work illegible from the outside):

- **Type** — `bug`, `documentation`, `enhancement` (GitHub's own defaults), or `process` for an architecture/workflow-process change that doesn't fit the other three. Orthogonal to `epic`: an epic can carry both `epic` and a type label (e.g. `process`+`epic`).
- **Status** — `status:backlog` (scoped, not started), `status:in-progress` (actively being worked, by this session or another), `status:blocked` (can't proceed — state the blocker in the issue body). Not a replacement for GitHub's own open/closed state; "done" is just closed, there's no `status:done` label.
- **Role** — `role:product`/`role:architect`/`role:qa`/`role:dev`/`role:reviewer` (canonical stage order per `skills/model-choice/SKILL.md`'s per-stage floors, QA before Dev — Test before Implementation), tracking which of the five multi-agent-workflow phases (`skills/role-contracts/SKILL.md`) is currently active on an issue/PR. Hand-maintained by the orchestrator, same as `status:*` — neither axis is set or cleared by a script; `role-label-staleness.sh` only *flags* a role label that's fallen behind the evidence, it doesn't fix it.

Both `status:*` and `role:*` are deliberately hand-maintained, not mechanized — issue #371 (automatic activation of the pipeline, in this release) leaves pipeline-phase state hand-maintained by the orchestrator, and any mechanization would be a separate decision from this convention existing. This-repo-only for now (not yet offered via `CHANGES.md`/`adopt.sh` to adopted projects) — validate the convention here first.

## Routing table

This file holds what every session needs. For everything else: the table below resolves every moved topic in a single jump.

| Situation | Skill |
|---|---|
| Quality review before the merge | `pre-merge-review` |
| Specifying work (PRD, test scenarios, issues), `Covers:` convention | `write-spec` |
| Substantiation requirement | `adoption-registry` |
| Adoption registry (tracking per project which changes apply) | `adoption-registry` |
| `check`/`deploy` naming convention, CI | `check-convention` |
| Deploy conditions per environment | `deploy-guards` |
| Complexity, technical debt, refactoring | `refactoring-triggers` |
| Test-first work: seams, red-before-green, anti-patterns | `tdd-seams` |
| Diagnosing a bug: reproduction → hypotheses → regression test → fix | `diagnose-bug` |
| Which model/reasoning effort to use for a pipeline stage | `model-choice` |
| Dispatching or reviewing a Product / Architect / QA / Fullstack Developer / Reviewer role (opt-in, `process-multi-agent-roles`) | `role-contracts` |
| Setting up a new (related) project | `adopt-workflow` (user-level) |
| Relentless, round-based requirement elicitation from Ties | `grilling` |
| Decomposing a system into deep modules, not shallow components | `codebase-design` |
| Release branch between work items and `main`: when, who merges what, completion review | `release-branch-workflow` |

## Why

Without this agreement, conflicts arise and work from one computer can accidentally be overwritten by work from the other. There is no technical block against direct pushes to `main` — so follow this workflow deliberately, even when a direct push would technically succeed.
