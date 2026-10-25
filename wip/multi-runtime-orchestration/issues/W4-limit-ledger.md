<!-- Draft. Title: "Limit ledger: normalized 5h/7d readings for both runtimes and a per-item budget log". Labels: process, enhancement, status:backlog. Release-branch member. -->

## Description
A read-only module returning one normalized record per runtime and window:
`{runtime, window: 5h|7d, used_pct|unknown, resets_at|unknown, observed_at, source}`. Readers:
Codex rollout `rate_limits` (version-tagged), and Claude via the user-level statusline tee
(the statusline command also writes its input JSON to a local file, atomically) with the
transcript limit text as fallback. Stale or unparseable readings are `unknown`, never 0, and
`unknown` counts as no headroom. Limit readings stay local per machine. When a work item
finishes, the % of each runtime's 5h and 7d window used during it is logged.

## Acceptance criteria

### AC1: Normalized readings
- Given a Codex rollout and a Claude statusline file
- When the ledger is read
- Then it returns both runtimes' 5h and 7d records with `observed_at` and source

### AC2: Fail closed
- Given a missing, stale or unparseable reading
- When the ledger is read
- Then that record is `unknown` (never 0 and never "reset now"), and the assignment rule treats it as no headroom

### AC3: Per-item budget log
- Given a work item finishes
- When its Pipeline log is closed
- Then it records the % used of each runtime's 5h and 7d window during the item, or `unknown`

### AC4: Statusline tee is safe
- Given several Claude sessions render the statusline at once
- When they write the tee file
- Then the file is always a complete JSON document (temp file + rename)

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W0, W1
**Blocks:** W6, W7
**Size:** M
**Runtime fit:** Claude (not small; the Codex reader alone could be split off as a small Codex-specific item at Planning)
