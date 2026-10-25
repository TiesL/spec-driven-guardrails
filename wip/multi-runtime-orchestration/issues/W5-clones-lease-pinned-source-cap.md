<!-- Draft. Title: "Clone per work item, issue lease, pinned workflow source and the concurrency cap". Labels: process, enhancement, status:backlog. Release-branch member. -->

## Description
The manager provisions one full clone per work item (adoption refuses linked worktrees), adopted
against a pinned workflow-source clone at `main` (never the release branch or a dev clone) for
SDG self-development. A lease per issue (owning session id in the Pipeline log plus
`status:in-progress`) keeps two sessions off one issue. The cap counts running sessions only,
2 in total in any mix, configurable; adopted operator-started running sessions count. Clones are
cleaned up after merge or abandonment.

## Acceptance criteria

### AC1: Own clone, pinned source
- Given a queued SDG work item
- When the manager starts it
- Then it runs in its own clone, its workflow source is the pinned `main` clone, and the source SHA is recorded

### AC2: Lease
- Given an issue already leased by a live session
- When the manager would start another session on it
- Then it does not, and logs why

### AC3: Cap of 2, paused items free a slot
- Given 2 running sessions in any mix and a third queued item
- When nothing pauses, then the third is not started; when one pauses on a decision or a short wait, then it is
- And the cap value comes from configuration, not code

### AC4: Cleanup
- Given a work item merged or abandoned
- When the manager next runs
- Then its clone is removed and its lease released

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W1, W3
**Blocks:** W6, W9
**Size:** M
**Runtime fit:** Claude (not small)
