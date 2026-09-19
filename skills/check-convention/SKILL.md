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
   (typecheck, lint, tests, build), exposed as an executable `check` at
   the project root, whatever stack the project is actually on. The
   GitHub Actions workflow (see `templates/ci.yml`, automatically
   scaffolded by `adopt.sh` once the project has that executable — #248,
   not gated on `package.json` specifically) calls `./check` directly and
   doesn't invent any separate checks of its own — one source of truth,
   no drift between local and CI.
2. **`deploy`** — actually rolls out to a target environment. Always
   remains a deliberate, manually started step: no automatic rollout on a
   merge — the same kind of control as the agreement that a merge only
   happens after Ties' explicit confirmation (see "Wrapping up" in
   `WORKFLOW.md`). See the `deploy-guards` skill for the conditions under
   which `deploy` may run.

Project-specific checks (a custom lint rule, a domain-specific validation)
belong in the project's own `check` script, not in `spec-driven-guardrails`.

`templates/ci.yml`'s own setup steps (`actions/setup-node`, `npm ci`) are
conditional on `package.json` existing — a project on a different stack
skips them and goes straight to `./check`, which is responsible for
knowing its own stack's tooling either way. `adopt.sh` scaffolds `ci.yml`
(and the stack-agnostic `check-pr-issue-link.sh`/`check-main-via-pr.sh`
alongside it) once the project has an executable `check` at its root —
any stack, not gated on `package.json` (#248).
