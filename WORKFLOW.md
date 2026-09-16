# Method — Git/GitHub Workflow

This project is developed from multiple computers. Follow this workflow in every session, regardless of which machine you're working on. This text is symlinked as `CLAUDE.md` in adopted projects — see `README.md` in this repo for the adoption procedure.

## Branch strategy: GitHub Flow

- `main` is always stable/working. **Never commit or push directly to `main`** — this is a workflow agreement, not a technically enforced rule (GitHub branch protection on private repos requires a paid plan).
- All work happens on a short-lived branch from the current `main`, named after the issue it implements:
  - `feature/<issue-number>-<kebab-case-description>` for new functionality/epics
  - `fix/<issue-number>-<kebab-case-description>` for bug fixes (including trivial ones, such as documentation corrections)
- **No request leads straight to development.** What's being built is specified in an issue first — see the `write-spec` skill for the epic/work-item templates. The branch name can't even be written without that issue's number, and `git-guardrails`/the native `pre-commit` hook enforce the pattern.

## When starting a session

1. `git fetch origin` (also happens automatically via a `SessionStart` hook, see `settings/session-hooks.json`).
2. Check whether you're continuing existing work (existing feature branch) or starting something new.
   - Existing work: `git checkout <branch> && git pull origin <branch>`.
   - New work: create the issue first — `gh issue create` with the epic or work-item template (`templates/ISSUE_TEMPLATE/`, see `write-spec`) — then branch from its number: `git checkout main && git pull origin main && git checkout -b feature/<issue-number>-<name>` (or `fix/<issue-number>-<name>`).
3. Review recent history for context: `git log --oneline -10` — especially useful if you're continuing on the other computer and want to see what's happened since last time.

## During the work

- Commit logical steps on the feature branch.
- Push regularly to `origin/<branch>` — never to `main`. This also happens automatically: a `SessionEnd` hook pushes the current branch when a session ends, with a guard that skips this when `main` happens to be checked out (extra safety net, since there's no branch protection — see below).
- Commit messages carry no "Co-Authored-By" trailer — enforced via `attribution.commit: ""` in `settings/session-hooks.json`, not dependent on whether the executing session remembers to do so.

## Wrapping up

1. Once the change is complete and tested (and, where applicable, manually verified): open a PR with `gh pr create`. If the PR refers to an issue (`Closes #N`), put that link in the **PR description itself**, not only in a commit message: GitHub populates `closingIssuesReferences` — the field that issue-linking checks actually test against — exclusively from the PR title/body. A commit with `Closes #N` does close the issue on a merge to `main`, but such a check won't see the link while the PR is still open.
2. **Run the quality review immediately, in parallel with CI, not gated on CI being green** — don't ask whether to, don't wait to be asked, don't wait for CI first; see the `pre-merge-review` skill. The review's marker is pinned to the commit it reviewed, so a commit that lands afterward (a fixup, or a fix for a red CI) simply needs a fresh review, whenever it runs — nothing slips through unreviewed.
3. Before asking for merge confirmation, know that CI has actually finished — the merge guard blocks the merge otherwise, and asking prematurely just costs a round trip. Don't poll `gh pr checks` on a short fixed interval — measured against this repo's own last 10 completed CI runs (`gh run list --json createdAt,updatedAt`), durations cluster at 5.5-8 minutes (one outlier at ~23min), so a 20s interval produces a dozen-plus "still pending" checks before CI ever finishes (issue #215). Instead: first check no sooner than 5 minutes after the run starts, then every 1 minute until it reaches a terminal state.
4. **Wait for Ties' explicit confirmation** that the test succeeded and there's no regression, before merging. Never merge automatically without that confirmation.
5. Then merge with `gh pr merge --squash --delete-branch` — this keeps the history on `main` clean and cleans up the branch (local and remote) immediately.

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
| Setting up a new (related) project | `adopt-workflow` (user-level) |

## Why

Without this agreement, conflicts arise and work from one computer can accidentally be overwritten by work from the other. There is no technical block against direct pushes to `main` — so follow this workflow deliberately, even when a direct push would technically succeed.
