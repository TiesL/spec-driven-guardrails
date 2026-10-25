<!-- Draft. Title: "Offer the manager to adopted projects via CHANGES.md". Labels: process, documentation, status:backlog. Release-branch member; starts only after W9 passes. -->

## Description
After the SDG proof run, offer the manager to adopted projects: a `CHANGES.md` entry with an
opt-in row for `WORKFLOW-ADOPTION.md`, and adoption docs stating macOS only, the user-level
statusline tee each adopter must set up, and the pinned-workflow-source rule.

## Acceptance criteria

### AC1: Opt-in offer
- Given W9 passed
- When an adopted project's session reports pending workflow changes
- Then it is offered the manager as an opt-in row, not applied by default

### AC2: Limitations stated
- Given the offer text
- When an adopter reads it
- Then it states macOS only (launchd), the statusline tee as a user-level change, and that the workflow source must be a pinned clone, not a dev clone

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W9
**Blocks:** none
**Size:** S
**Runtime fit:** either (small, so Codex-eligible)
