<!-- Draft. Title: "Runtime session adapter for Claude Code and Codex work-item sessions". Labels: process, enhancement, status:backlog. Release-branch member. -->

## Description
One interface the manager uses to drive a work-item orchestrator session on either runtime:
`start(clone, brief, model)`, `status(handle)` → working | needs-human(question) |
done(report) | limited(resets_at or unknown) | failed(reason), `resume(handle, message)`,
`identity(handle)` (origin and #503 record). Two adapters: Claude (`claude --bg`, `--resume`,
`claude agents --json`, job `state.json`) and Codex (`codex exec`, `exec resume`, rollout
parsing, stdin redirected, no `--ephemeral`). Operator-started sessions are adopted read-only.
The adapter refuses any brief carrying merge authority into `main` and never resumes a Reviewer
session. Tests use fake `claude`/`codex` executables on PATH and sanitized fixtures. The
Architect may split this into a Claude and a Codex item at Planning.

## Acceptance criteria

### AC1: Start records origin
- Given a clone and a brief
- When the manager starts a session on either runtime
- Then the handle's identity records runtime, model, session/thread id, origin `agent-started` and workflow-source SHA

### AC2: Adopted session
- Given a session the operator started
- When it is adopted
- Then its identity records origin `operator-started` and the adapter never sends it a start

### AC3: Status distinguishes a question, a limit and a failure
- Given a session that stopped with a question, one that hit a usage limit, and one that failed (overload, auth)
- When `status` is read
- Then they return needs-human with the question, limited with the reset time or `unknown`, and failed with the reason, never confused with each other

### AC4: No merge authority, no resumed Reviewer
- Given a brief that grants merge authority into `main`, or a handle tagged Review
- When `start`/`resume` is called with it
- Then the adapter refuses and says why

### AC5: No stdin hang
- Given a headless Codex start with no TTY
- When it runs
- Then it does not wait on stdin

## Related
**Epic:** #
**Covers:** <to be assigned by Product/QA at Discovery>
**Blocked by:** W0, W1
**Blocks:** W5, W6, W7
**Size:** L
**Runtime fit:** Claude (not small)
