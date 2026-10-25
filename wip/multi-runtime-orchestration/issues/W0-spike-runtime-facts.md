<!-- Draft. Title: "Spike: confirm the unverified runtime facts for multi-runtime orchestration". Labels: process, status:backlog. Release-branch member. -->

## Description
The design rests on facts marked [U] in ARCHITECT-REPORT.md and ARCHITECT-REVIEW.md. Probe each
live on this machine and record the result as a #503-style observation record (surface, version,
command, outcome), so later items build on verified behaviour. No production code.

Facts to confirm:
1. A successful `codex exec --json` stream carries `token_count`/`rate_limits`.
2. `codex exec resume <thread_id>` works after a limit reset.
3. `claude --bg --resume <id>` behaviour after a limit hit.
4. Claude statusline input carries reset times for the 5h/7d windows.
5. A Claude Code Remote Control notification reaches the maintainer's phone.
6. A launchd-started Claude manager can be a Remote Control session.
7. Whether Codex `spawn_agent` accepts a reasoning-effort argument.

## Acceptance criteria

### AC1: Every fact has a recorded verdict
- Given the seven facts above
- When the spike ends
- Then each is recorded as verified, refuted or still unknown, with the command, CLI version and observed output (no secrets, tokens or account ids)

### AC2: Refuted facts name what they affect
- Given a fact is refuted or still unknown
- When it is recorded
- Then the record names the affected epic AC and work item, and a refuted fact 5 or 6 is flagged to Product to reopen the push channel

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** none
**Blocks:** W1, W3, W4, W6, W7
**Size:** S (Architect estimate: S ≤ 1 day, M 2-3 days, L 4+ days, through the five-role pipeline)
**Runtime fit:** Claude (half the probes need a Claude manager and Remote Control)
