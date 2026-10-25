<!-- Draft. Title: "SDG proof run: an unattended overnight queue on one machine". Labels: process, status:backlog. Release-branch member. -->

## Description
Run the manager on SDG itself, on one machine, overnight, with a queue of at least three real
SDG work items, and record the run on this issue. It is the epic's acceptance (AC-13) and the
precondition for W10 and for the release branch's holistic review.

## Acceptance criteria

### AC1: Overnight run survives a limit and a decision
- Given a queue of at least three real SDG items on one machine, unattended overnight
- When at least one usage limit hits and one decision is answered from the phone through the manager chat
- Then every item is merged into the release branch, or reaches an open PR with an approving review, or stops with a recorded human stop; no work is lost

### AC2: No merge into main
- Given the whole run
- When its record is checked
- Then nothing was merged into `main`, and every release-branch merge passed the W2 ancestry check

### AC3: The record is complete
- Given the run ends
- When its record is written
- Then it lists per item: runtime, models, origin, waits and switches, decisions relayed, and % budget used per runtime

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W2, W5, W6, W7
**Blocks:** W10
**Size:** S (plus the overnight run itself)
**Runtime fit:** n/a (operational, run by the maintainer with the manager)
