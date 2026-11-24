<!-- Draft. Title: "Merge guard: refuse a PR that is not up to date with its base; pre-given merge permission is no confirmation". Labels: process, enhancement, status:backlog. NOT a release-branch member: merges to main directly (see epic). -->

## Description
Parallel work items can take the same S/F/A number. CI does not re-run when the base moves, so a
stale green run could merge a duplicate. SDG's `main` already has strict required checks, but
release branches and private adopted projects do not. Add one check to the existing merge guard
(`hooks/git-guardrails`, which already gates `gh pr merge`): refuse when the base branch tip is
not an ancestor of the PR head. The remedy is `gh pr update-branch` (a merge, no force-push)
and green CI on the new head. A clash that then goes red is renumbered through the ordinary
finding route.

In the same item, add one sentence to the merge rule (CLAUDE.md / WORKFLOW wrapping-up step 4):
a merge permission given in advance or on conditions is not a confirmation of a merge into
`main`; the confirmation comes after the final PR head is known and names it; any such autonomy
belongs to #511. Offer both to adopted projects through a `CHANGES.md` entry.

This lands on `main` before the release branch takes unattended merges, because the guard that
runs comes from the pinned workflow source (`main`).

## Acceptance criteria

### AC1: A stale PR is refused
- Given a PR whose base tip is not an ancestor of its head
- When `gh pr merge` runs for it, into `main`, a `release/*` branch or an adopted project's base
- Then the merge guard refuses and names `gh pr update-branch` as the remedy

### AC2: An updated PR passes this check
- Given the same PR after `gh pr update-branch`, with a review marker and green CI on the new head
- When `gh pr merge` runs
- Then this check does not block it

### AC3: No force-push is needed
- Given the remedy the guard names
- When it is followed
- Then the PR branch is updated without a force-push

### AC4: Pre-given permission is written down as no confirmation
- Given the merge rule in CLAUDE.md / WORKFLOW
- When a reader looks up what counts as confirmation of a merge into `main`
- Then it states that a permission given before the final head existed, or on conditions, does not count, and points to #511

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** none
**Blocks:** W9
**Size:** S
**Runtime fit:** either (small, so Codex-eligible)
