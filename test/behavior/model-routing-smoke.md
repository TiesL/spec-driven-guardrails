# Model routing live smoke test (#707, AC12, S712)

Status: **PASS**. This protocol starts real model children and reads the real
Caveman proxy's request store, so it uses subscription usage and needs the
machine's proxy. It is deliberately not run by `./check` or CI, and no case in
`test/cases/` starts a real model, Codex or the proxy:
`test/cases/s712_route_live_smoke_protocol.sh` checks the structure of this file
only. The recorded result below is the run that backs the claim "routed
children are metered and their text arrives uncut"; the protocol itself is
not run by `./check` or CI.

The design is A61 in `ARCHITECTURE.md`; the user-facing description is
`docs/model-routing.md`.

## Preconditions

1. The project the children run in answers `process-model-routing` with `yes`
   in its `WORKFLOW-ADOPTION.md`, and `process-multi-agent-roles` with `yes`.
2. The Caveman proxy is running and listening on the loopback port the wrapper
   probes (`route-child.sh` holds the address; do not copy it into scripts).
3. The Orchestrator session that runs this protocol is direct: its own
   `ANTHROPIC_BASE_URL` is unset (the wrapper refuses otherwise, exit 4), and no
   settings file in the wrapper's checked list sets `env.ANTHROPIC_BASE_URL`.
4. A scratch directory inside that project holds a copy of
   `skills/role-contracts/SKILL.md` (a real contract file, large enough that the
   proxy would compress it without the pass-through header).
5. Note the highest `id` in the proxy's `requests` table before starting (read
   only, see step 4), so the rows of this run can be told apart.

## Steps

1. Claude child, routed:
   `"$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" claude -- claude -p --model haiku --no-session-persistence "<prompt>"`,
   where the prompt asks the child to read the copy of
   `skills/role-contracts/SKILL.md` in full and to report whether any text in it
   reads `elided` or carries a `<<ccr:` marker, and to quote its last line.
2. Codex child, routed:
   `"$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" codex -- codex exec --ephemeral "<same prompt>"`.
3. Codex child, off switch:
   `SDG_MODEL_ROUTE=off "$SPEC_DRIVEN_GUARDRAILS_DIR/route-child.sh" codex -- codex exec --ephemeral "<a short prompt>"`.
4. Evidence: read-only access (`sqlite3 -readonly`) to `~/.caveman/caveman.db`
   table `requests`, counts and these columns only: `id`, `provider`,
   `compression_eligible`, `raw_request_sha256`, `transformed_request_sha256`,
   and the row timestamps. Never read request or response contents, headers or
   secrets.

## Pass conditions

All must hold; any miss is FAIL.

- At least one new row with provider `anthropic` for the Claude child of step 1.
- At least one new row with provider `chatgpt-subscription` for the Codex child of step 2.
- Every row of steps 1 and 2 has `compression_eligible = 0`, and its
  `raw_request_sha256` equals its `transformed_request_sha256`.
- There is no row for the Orchestrator session in the run's window (only the
  children are routed).
- The `off` Codex child of step 3 adds zero rows.
- Each child that read the contract file reports no elision marker and quotes
  the file's true last line.

## Recorded result

A run that claims PASS or FAIL fills in every field below; a file that claims
either without them, or with an implausible value, fails S712. A file with no
recorded run keeps every field `none` and Status UNRUN.

- Date: 2026-11-19
- Head SHA: 4525fc501410075ec14633d90311a512a9515350
- Proxy version: 4.1.0 (bin-v4.1.0)
- Row ids: 3708-3713
