---
name: release-branch-workflow
description: >
  When and how to use a release branch between work-item branches and
  `main`: the trigger (a recorded Product+Architect judgment call, no
  numeric threshold), who may merge what into it, the frozen membership
  set, the mandatory holistic review before it can go to the project
  maintainer for the final merge decision, and the version-bump proposal
  that merge carries. Use this when an epic is being scoped, or when an
  in-flight epic turns out to need this tier partway through.
---

# Release-branch workflow

A release branch is an optional third tier between short-lived work-item branches
(`feature/<n>-...`/`fix/<n>-...`) and `main`, for an epic whose work items are
easier to land, review, and version together than one at a time. Most epics never
need one — a work item merges straight to `main` once it's reviewed and CI is
green. This skill is for the minority that do.

## When to open one

There is no numeric threshold (issue count, file count, or otherwise) — a fixed
number invites exactly the kind of per-epic second-guessing this project's own
review-depth classifier deliberately avoided for the same reason (see
`classify-review-depth.sh`'s own design notes). Instead: Product and Architect
make an explicit, recorded judgment call, written into the epic issue itself,
either —

- **at design time**, when the epic is first scoped and its own PRD/architecture
  work already shows multiple work items that belong together as one release, or
- **mid-flight**, when an epic that started as ordinary work items targeting
  `main` grows, partway through, into something that warrants the same
  treatment.

Either way, the call and its reasoning go on the epic issue, not just in an agent's
own working notes — a future reader (human or agent) should be able to see why a
release branch exists for this epic without reconstructing the decision.

## Opening a release branch

Branch name: `release/<epic-issue-number>-<kebab-case-slug>`, forked from the
current tip of `main` — same naming shape as `feature/`/`fix/`, one level up.

**Membership freezes at this point.** The set of issues this release branch
covers is exactly the epic's work items as they exist the moment the branch is
opened (or the moment a mid-flight epic is promoted into this tier). An issue
discovered afterward and given the epic's label does not automatically become
part of *this* release — it's tracked under the epic for the next one, unless
Product/Architect explicitly pull it in with the same kind of recorded
decision that opened the branch in the first place. This keeps "the release is
done" a real, checkable condition instead of a moving target.

**Mid-flight promotion**: if work-item PRs are already open against `main` when
the epic crosses into needing a release branch, retarget them —
`gh pr edit <pr> --base release/<n>-<slug>` — rather than letting some land on
`main` and others on the release branch. No rebase is needed; the release branch
forks from the same point those PRs already branched from.

## Merging into the release branch

Any role, or an orchestrating session on its own judgment, may merge a
work-item PR into the release branch once:

- CI is green, and
- all tests pass.

No separate human confirmation is required per work item here — this is
deliberately lower-ceremony than the release branch's own merge into `main`
(below). The existing merge guard (review marker + CI status) still applies the
same way it does for any other PR.

**Release branches stay unprotected** — no GitHub branch-protection rules. This
matches the low-ceremony merge path above: protection (required reviews,
required status checks blocking even a merge attempt) is the opposite of what a
judgment-call merge path needs. For a typical adopted project this is doubly
true for a different reason: most adopted projects are private repositories on
a free plan, where GitHub branch protection isn't available at all regardless
of what the project would otherwise choose. (This project's own `main` is the
exception — public, with real protection — because it's a public repository;
that reasoning doesn't carry over to a typical private adopted project, but the
practical outcome — nothing to configure here — is the same either way.)

## Completing a release branch

Once every issue in the frozen membership set (above) is merged into the
release branch:

1. **A full holistic review runs before anything goes to the maintainer.**
   Dispatch QA and Reviewer fresh (not re-reviewing individual work items,
   which already had their own per-PR review) — scoped to the release branch's
   entire accumulated diff against `main`. QA re-checks the epic's functional
   and non-functional requirements in aggregate; Reviewer does the final
   evidence/quality gate on the whole.
2. **This review always runs at thorough depth, unconditionally** — no
   `classify-review-depth.sh` call. A release-branch gate is the last check
   before `main`, regardless of what any individual work item's own trigger
   category was.
3. **Propose the version bump.** Read the release branch's accumulated
   `CHANGELOG.md` entries and propose a SemVer bump type (patch/minor/major)
   under the project's existing versioning rules. This is a proposal, not a
   decision — see below.

## Merging the release branch into `main`

This is always the project maintainer's explicit call — never automatic, and
never inferred from an earlier, unrelated approval. Once the holistic review
above is clean and CI is green:

- Present the release branch as ready, along with the proposed version bump.
- Wait for explicit confirmation.
- The maintainer's confirmation covers both the merge itself and the version
  bump proposal in one step — don't make this two separate round-trips.
- After merging, tag the release per the project's own tagging convention.

## What this skill does not cover

This skill is procedural guidance, not a script — nothing here is
mechanically enforced beyond the existing merge guard (CI + review marker),
which already applies to every PR regardless of its base branch. If your
project's own merge guard still treats an already-closed issue as "stray"
when referenced from a release-branch-base PR's commits, that's a defect in
the guard itself, not something this skill works around — see
`hooks/git-guardrails`'s own handling of this.
