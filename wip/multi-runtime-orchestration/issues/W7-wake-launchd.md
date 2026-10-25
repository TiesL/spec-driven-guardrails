<!-- Draft. Title: "Wake via launchd: resume the manager after a limit reset (macOS only)". Labels: process, enhancement, status:backlog. Release-branch member. -->

## Description
A launchd one-shot that starts a fresh manager from artifacts and the ledger after a reset.
The wake script itself uses no LLM: it reads the ledger first and, if Claude is still limited,
re-arms instead of starting a manager that cannot spend a turn. Exactly one pending wake per
manager. No wake prompt carries merge authority. macOS only, stated as a limitation; no
non-launchd seam is introduced.

## Acceptance criteria

### AC1: Wake after reset
- Given the manager stopped on a Claude limit with a known reset
- When the reset passes
- Then launchd starts a fresh manager that resumes from artifacts, with no human action

### AC2: Still limited, re-arm
- Given the wake fires while the ledger shows Claude still limited or `unknown`
- When the wake script runs
- Then it starts no manager and schedules one new wake (fail closed: next 5h boundary plus a margin when the reset is unknown)

### AC3: One wake, no merge authority
- Given any number of scheduling calls
- When the pending wakes are listed
- Then there is at most one per manager, and its command carries no merge authority

### AC4: Codex continues meanwhile
- Given Claude is out and Codex orchestrators are running
- When the manager is down
- Then those orchestrators continue to their own end, and each can be driven directly by the maintainer from its artifacts

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W3, W4, W6
**Blocks:** W9
**Size:** M
**Runtime fit:** Claude (Claude-specific wake target; not small)
