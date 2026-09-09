---
name: deploy-guards
description: >
  The conditions under which deploy to pre-production or production may
  run (clean working tree, check passes, main equal to origin/main, green
  CI), and why. Use this when building or changing a deploy script, or
  when a deploy is refused.
---

## `deploy` refuses to run from an unverified state

`deploy` checks for itself whether the state is sound and stops if it
isn't. Which conditions apply depends on the target environment.

**Pre-production (acceptance) — may run from any branch.** The environment
where acceptance testing happens, before the merge. Conditions: the
working tree is clean (what you roll out is traceable to a single commit —
otherwise you don't know *what* you tested); `check` passes (`deploy` runs
it itself, instead of trusting that you remembered to); the commit is
pushed (so CI sees it, and what was in acceptance can be found again). A
green CI run is deliberately *not* a condition here — `check` just ran
locally, and waiting on every iteration makes the loop slow.

**Production — only from `main`.** Everything above, plus: you're on
`main` (only then has the code gone through a PR and been reviewed); local
`main` equals `origin/main` (otherwise you roll out something CI never
saw, or something outdated); the latest CI run on `main` succeeded.

If a project has more than one target environment, there is **no implicit
default** — the environment is passed explicitly every time. A default
value you can forget is exactly the mechanism being abolished here.

Checks that need the network (CI status, remote freshness) warn and
proceed if tooling or connectivity is missing; the purely local checks
block hard. There is one deliberate escape hatch (`--force` or equivalent)
that loudly reports *which* checks are being skipped and to *which*
environment — a guard without an escape hatch eventually gets bypassed by
editing the script instead, and that's worse than a guard you turn off
explicitly.

### The order in practice

1. Work on a feature branch; commit and push.
2. Deploy that branch to **pre-production**; do the acceptance test there.
3. If that goes well: Ties initiates the merge to `main` (see "Wrapping
   up" in `WORKFLOW.md`).
4. Deploy `main` to **production**, after Ties' explicit approval.

Without a pre-production environment, step 2 and the "Wrapping up"
agreement conflict: verification can then only happen in production, but
you're only allowed there after the merge. Don't let that tension linger —
choose deliberately: use the escape hatch for that one rollout and say
out loud that you're doing so, or set up a pre-production environment. The
latter is the intent.

### Why these rules exist

A `deploy` that doesn't look at git rolls out whatever happens to be in
the working tree — regardless of branch, commit, or CI. If a periodic
trigger then runs on that code, unreviewed code executes itself; a
confirmation step in a UI only protects the manual route, not the
automatic one. This went wrong once in `tennis-admin`, and the only
safeguard up to that point was that whoever deployed remembered to check.
That's not a safeguard. Worked-out example: `scripts/deploy.mjs` in
`tennis-admin`.
