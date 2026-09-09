---
name: check-convention
description: >
  The fixed, platform-neutral command names check and deploy, and how CI
  calls them without inventing its own checks. Use this when setting up or
  changing CI, or when unsure where a project-specific check belongs.
---

## Automating testing and deployment

For projects with buildable/testable code, two fixed, platform-neutral
command names apply:

1. **`check`** — everything that decides whether a change is good
   (typecheck, lint, tests, build). The GitHub Actions workflow (see
   `templates/ci.yml`, automatically scaffolded by `adopt.sh` if the
   project has a `package.json`) calls this command and doesn't invent any
   separate checks of its own — one source of truth, no drift between
   local and CI.
2. **`deploy`** — actually rolls out to a target environment. Always
   remains a deliberate, manually started step: no automatic rollout on a
   merge — the same kind of control as the agreement that a merge only
   happens after Ties' explicit confirmation (see "Wrapping up" in
   `WORKFLOW.md`). See the `deploy-guards` skill for the conditions under
   which `deploy` may run.

Project-specific checks (a custom lint rule, a domain-specific validation)
belong in the project's own `check` script, not in `spec-driven-guardrails`.

This template assumes npm. For a project on a different stack, the same
principle applies (fixed `check`/`deploy` names, CI only calls `check`),
applied with that stack's own tooling — `adopt.sh` only scaffolds `ci.yml`
when a `package.json` is present.
