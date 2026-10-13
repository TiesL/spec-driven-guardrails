# Runtime dry-run evidence for #455

All rows below are **unobserved** in this implementation session. Automated
filesystem fixtures and configured CI checks are structural evidence only.
A human must replace each status with a linked observation before release
review can treat the corresponding acceptance criteria as evidenced.

| Surface | Status | Required observations |
| --- | --- | --- |
| Codex CLI | unobserved | S289, S292–S296, S298: fresh guidance/skill/context reads; precedence and budget negatives; available fresh roles; unavailable dispatch stop; resume; every finding route and two-round Architect step; uninterrupted ordinary handoffs; genuine decision/override/main-merge stops |
| Codex desktop | unobserved | S290, S292–S296, S298: same installation in a restarted fresh session; matching/nonmatching skills; trust enabled/withheld; same loading, dispatch, resume, route, continuation and stop observations as CLI |
| Claude Code | unobserved | S297: default/repeated adoption; legacy backups; fresh/resumed work; representative SessionStart/Bash PreToolUse/PostToolUse/SessionEnd and native Git/CI behavior; fresh Review and finding loop-back |
| second machine | unobserved | S292: actual independent machine, local checkout/revision/OS, before/after status, missing clone-local links and owned stale-link repair, preserved answers/project bytes, actual guidance loading |

For each run record:

- Date, exact runtime/product and version, OS, install mode and configuration;
  trust, permissions, instruction budget and parent/root/deeper instruction files.
- Workflow checkout revision and machine-local path, project branch/revision,
  public adoption/status output and fresh/restarted session evidence.
- Which policy rules, session-context output and invoked SKILL.md files were
  actually read before dependent work; nonmatching skills are not presumed used.
- Attempted action and observable result: distinguish absent capability, failed
  attempt and observed behavior. Include prompts and actual dispatch/session ids.
- Stage chain, each Review's artifact-only brief, finding links/slugs and class
  routes; two consecutive medium/high rounds and Architect reset; low-only and
  interrupted controls; resume from durable artifacts with an open later route.
- Unavailable dispatch stop and human stop/override decision, where applicable
  numbered bounded decision, pushback and Architect risk note; no fabricated
  emitter records or inferred consent. Main merge always awaits confirmation.
- Limitations, missing guidance, failed reads and unobserved variants. A routine
  “continue?” pause at a required ordinary handoff fails S298 continuation.

Codex web, third-party hosts and native Windows are outside the supported scope.
One-host two-path fixtures cannot establish a second-machine or additional OS
result. Version-specific discovery failures return to Architect without copied
skill bodies. Existing Claude baseline observations in README remain historical
baseline evidence, not a new #455 Claude dry run.
