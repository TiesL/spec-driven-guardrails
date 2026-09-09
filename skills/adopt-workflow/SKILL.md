---
name: adopt-workflow
description: >
  The adoption question: whether a project should use the shared workflow
  from spec-driven-guardrails, and how to set up a new (related) project.
  User-level
  skill, installed by `adopt.sh --user`. Use this at session start in a
  git project that isn't adopted yet, or when setting up a new project.
---

## The adoption question

Check at the start of a session in a directory that is a git repository:

1. Is this repo itself `spec-driven-guardrails`? If so: skip this check.
2. Does this project already have a `CLAUDE.md` that is a symlink to
   `spec-driven-guardrails/WORKFLOW.md`? If so: already adopted, skip this
   check.
3. Is there already a known choice for this project recorded in the memory
   system (previously answered "yes" or "no")? If so: follow that choice
   without asking again.
4. Otherwise: ask Ties once whether this project should use the shared
   personal workflow (`spec-driven-guardrails`).
   - **Yes** → run `spec-driven-guardrails/adopt.sh` from the root of this
     project (requires `SPEC_DRIVEN_GUARDRAILS_DIR` to be set as an
     environment variable — see `spec-driven-guardrails/README.md` if it
     isn't yet).
   - **No** → leave the project alone: the project's own conventions
     remain leading, or there's no specific workflow agreement.
   - Record the choice (yes/no, and for which project) as memory, so the
     question isn't asked again every session.

This question is deliberately *not* silent/automatically enforced — team
or work projects that don't belong to Ties alone shouldn't receive this
workflow unsolicited.

## Setting up a new (related) project

1. `gh repo create <name> --private --source=. --remote=origin` — creates
   an empty GitHub repo, initializes git locally (`git init`), and adds
   the remote (`git remote add origin <URL>`) in one step. Use `git init`
   + `git remote add origin <URL>` separately only if the GitHub repo
   already exists or was created outside `gh`.
2. Adopt this shared workflow via `adopt.sh` in this repo
   (`spec-driven-guardrails`) — see the adoption question above and
   `README.md`.
