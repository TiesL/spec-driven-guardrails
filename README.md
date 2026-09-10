# spec-driven-guardrails

(Formerly `claude-workflow` — renamed in W32/#56, see PRD.md "Besloten in W29 (#53)", decision 1.)

One, version-controlled source of truth for the personal Git/GitHub workflow that Ties uses with Claude Code in all his solo projects (not in team/work projects). This workflow used to be duplicated in every project (`CLAUDE.md` + `.claude/settings.json`), which led to drift — this repo solves that.

## Contents

| File | Purpose |
|---|---|
| `WORKFLOW.md` | The workflow text itself (GitHub Flow, branch+PR, session steps, specification process) plus a routing table that points every moved topic to its skill. Symlinked as `CLAUDE.md` in adopted projects. |
| `settings/session-hooks.json` | `SessionStart`/`SessionEnd` hooks + `attribution.commit` setting. Symlinked as `.claude/settings.json`. |
| `hooks/` | `git-guardrails` — the `PreToolUse` guard against destructive git commands, and (W10b) the merge guard on `gh pr merge` without a review marker or with non-green CI. Always fails open (no `gh`/network, missing tool) — a broken guard must never block work. Invoked from `settings/session-hooks.json`. |
| `skills/` | The nine Claude Code skills (`pre-merge-review`, `deploy-guards`, `check-convention`, `adoption-registry`, `write-spec`, `refactoring-triggers`, `tdd-seams`, `diagnose-bug`, `adopt-workflow`) — see the routing table in `WORKFLOW.md`. `adopt.sh` symlinks each of them into `.claude/skills/` of every adopted project. |
| `USER-CLAUDE.md` | Short trigger instruction for the automatic adoption prompt on new projects. Symlinked as `~/.claude/CLAUDE.md`. |
| `templates/PRD.md`, `templates/TEST-SCENARIOS.md`, `templates/ARCHITECTUUR.md` | Generic templates for specifying a project (see the `write-spec` skill). The PRD requires answering fifteen non-functional questions and separates *Bekende beperkingen* from *Technical debt*; the test scenarios ask for failure paths alongside happy paths; `ARCHITECTUUR.md` records structural decisions and their revisit trigger. **Copied** on adoption, but only if the file doesn't already exist there — a filled-in copy is never overwritten. |
| `templates/ISSUE_TEMPLATE/` | GitHub issue templates (`epic.md`, `work-item.md`, `config.yml`), with notation aligned to `PRD.md`/`TEST-SCENARIOS.md`. **Copied** (refreshed) into `.github/ISSUE_TEMPLATE/` of the project on every adoption. |
| `templates/CONTEXT.md` | Optional glossary (project jargon → meaning), separate from `ARCHITECTUUR.md`, which covers structural decisions. Only scaffolded if the project answered `yes` to `process-context-document` in `CHANGES.md`. |
| `templates/ci.yml` | Generic GitHub Actions CI that only calls `npm run check` (see the `check-convention` skill). Scaffolded on adoption, but only if the project has a `package.json`. |
| `CHANGES.md` | List of adoptable changes: per PR-sized change, a closed question, an "applies if" condition, and what "ja" means. Projects record their answer in their own `WORKFLOW-ADOPTION.md` (or its pre-migration name, `WORKFLOW-ADOPTIE.md` — see W42/#114). |
| `CHANGES-ARCHIEF.md` | Retired `CHANGES.md` entries, with their ID unchanged so a project that once answered can still find where that row came from. |
| `nfr/` | The NFR registry: fifteen files, one per non-functional attribute (security, data integrity, failure modes, …). The sole source for both the `spec-*` questions in `CHANGES.md` and the filled-in subsections in `templates/PRD.md` — neither is tracked separately anymore. |
| `lib/` | Shared bash libraries: `changes.sh` (the `CHANGES.md` parser and predicates, used by both `adopt.sh` and `pending-changes.sh`) and `nfr.sh` (reads/validates the `nfr/` registry). |
| `pending-changes.sh` | Determines which changes from `CHANGES.md` and `nfr/` apply to a project and are still unanswered. Invoked by the `SessionStart` hook. |
| `adopt.sh` | Script that creates/refreshes the symlinks and copies above locally, and seeds the adoption table of a new project. |
| `check` | The only command this repo's own CI invokes: bash syntax, JSON validation, NFR registry drift, PR linkbacks, shellcheck (non-blocking), then the test suite. The same `check`/`deploy` naming convention this repo requires of adopted projects, applied here to itself. |
| `test/` | This repo's own test suite: `run.sh` (runs everything under `cases/`), `lib.sh` (sandbox and assert helper functions), and `fixtures/nulmeting/` (the frozen baseline, see `LEESMIJ.md` there). |
| `PRD-MULTI-AGENT-WIP.md` | **WIP** — exploratory PRD for multi-agent software development in a later release, linked to epic [#65](https://github.com/TiesL/claude-workflow/issues/65). Not part of the shared workflow machinery above, and not approved: directional, with open design questions deliberately marked as **TBD**. |

## Why local symlinks instead of committed symlinks

Project directories aren't in the same place on every computer (e.g. `~/Projects` on one, `~/Documents/ClaudeCodeZandbak` on the other). A symlink you commit to git (relative or absolute) can therefore never be correct on both machines at once. That's why the symlinks are **not committed**: `adopt.sh` creates them locally, with a path that's correct per machine via the `SPEC_DRIVEN_GUARDRAILS_DIR` environment variable.

## One-time setup per machine (Ties' own use: always follow `main`)

1. Clone this repo anywhere you like on the machine.
2. Set once in your shell profile (`~/.zshrc` or `~/.bashrc`):
   ```bash
   export SPEC_DRIVEN_GUARDRAILS_DIR="/full/path/to/spec-driven-guardrails"
   ```
   Restart your shell (or `source ~/.zshrc`) so the variable is active.
3. Set up the user-wide adoption-prompt trigger:
   ```bash
   "$SPEC_DRIVEN_GUARDRAILS_DIR/adopt.sh" --user
   ```
   From now on, Claude Code will automatically ask, when starting a session in a not-yet-adopted git project, whether that project should use this workflow.

This checkout keeps following `main` — this is Ties' own, ongoing
multi-machine use. If you want a specific, pinned version instead
(see below), that setup replaces steps 1-2 above.

## Installing a pinned version (for a user other than Ties)

If you don't want to get every change on `main` live, but instead stay on a
specific, tagged release until you decide to upgrade:

1. Clone this repo (as above, step 1).
2. Run from that clone:
   ```bash
   ./install.sh          # pins to the latest tag
   ./install.sh <tag>     # pins to a specific tag
   ```
   `install.sh` refuses to run on a dirty working tree (uncommitted
   changes), and clearly reports which tag it picked or why a
   given tag doesn't exist.
3. Follow the instruction `install.sh` prints at the end: set
   `SPEC_DRIVEN_GUARDRAILS_DIR` to this clone in your shell profile (step 2
   above, unchanged), and optionally set the user-wide trigger (step 3
   above).

Upgrading to a newer release: run `install.sh <new-tag>` again
in the same clone. This is functionally equivalent to Ties' own setup — both
result in a checkout that `adopt.sh` works against the same way —
only this clone never follows `main` automatically.

## Adopting a project

Existing project:

```bash
cd /path/to/project
"$SPEC_DRIVEN_GUARDRAILS_DIR/adopt.sh"
```

New project: first `gh repo create <name> --private --source=. --remote=origin`
(see the `adopt-workflow` skill for the `git init` variant), then the same
`adopt.sh` step.

This sets `CLAUDE.md` and `.claude/settings.json` as local symlinks, and adds them to that project's `.gitignore` (they're machine-specific references, not project artifacts). Existing files at those paths — if they aren't symlinks — are renamed to `*.bak` instead of overwritten.

### Known pitfall: branches older than the adoption

Git overwrites a local (untracked) symlink without warning as soon as you switch to a branch that still has `CLAUDE.md`/`.claude/settings.json` as a regular, tracked file (e.g. a feature branch created before this project was adopted). After switching back to such a branch, the symlinks are gone. Solutions:
- **Preferred:** merge/rebase `main` into that branch once this project is adopted — after that, the conflict disappears permanently for that branch.
- **Alternative:** run `adopt.sh` again every time this happens (idempotent, no risk).

## Templates: copy instead of symlink

Unlike `CLAUDE.md`/`.claude/settings.json` (local symlinks,
never committed), the files under `templates/` are **copied** into
each adopted project, with two different behaviors:

- **`PRD.md`/`TEST-SCENARIOS.md`** — scaffold: only created if the
  file doesn't already exist in the project. These are project-owned,
  fillable documents; a filled-in copy is never overwritten.
- **`ISSUE_TEMPLATE/*`** — always refreshed on every `adopt.sh` run. This is
  meta-configuration (GitHub issue forms), not fillable content.

A symlink wouldn't work here anyway for the issue templates: GitHub renders
them server-side from the repo content itself, not via local
filesystem symlinks. Consequence of "copy": after a change to a
canonical template in this repo, `adopt.sh` must be run again in every
project to refresh the issue-template copy there (idempotent, no
risk — the same kind of agreement as the known pitfall above).

## Adoption registry

Every adopted project tracks in `WORKFLOW-ADOPTION.md` which changes from
`CHANGES.md` it applies. A `SessionStart` hook reports what's still open;
Claude poses those as closed yes/no choices and records the answer.
See the `adoption-registry` skill (reachable via the routing table in `WORKFLOW.md`) for the full story.

Manual checking is also possible:

```bash
"$SPEC_DRIVEN_GUARDRAILS_DIR/pending-changes.sh" /path/to/project
```

The hook locates this repo via the symlink
(`readlink .claude/settings.json`), not via an environment variable — a
non-interactive shell doesn't load your `~/.zshrc`, so a hook can't
rely on that. If that symlink points to a directory that no longer exists (e.g. after a
rename before re-adoption), the `SessionStart` hook reports that explicitly
instead of silently running no hooks.
