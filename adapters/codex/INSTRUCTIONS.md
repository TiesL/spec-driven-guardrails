## Codex CLI and desktop runtime mapping

The policy above is embedded in the managed AGENTS.md block. Claude-specific
automatic hook statements in that policy apply to Claude's adapter. This Codex
adapter defaults to runtime-hooks: not-installed; runtime shell interception unavailable.
Explicit `adopt.sh --runtime codex --hooks` installs a managed Bash PreToolUse
merge hook pointing at the self-contained `.codex/sdg-guard/` copy. Only explicit
`--hooks` refreshes it; default adoption retains its installed revision. Status
reports current, stale (warning), corrupt (conflict), absent or recovery pending
(exit 1). Only a second explicit `--hooks` run recovers a pending refresh; default
adoption and status never recover or clean up staging. Interrupted preparation
rebuilds from the source available at retry time and records its new target digest.
Refresh verifies staging and atomically exchanges directories; unsupported exchange
refuses refresh. TiesL must refresh or recover outside the sandbox with no hook
executing, and prevent hook execution until completion. Exchange does not pin a
generation for concurrent hooks. Never work around that protection. The first migration needs
one further review/trust in `/hooks`; content-only refreshes are not re-prompted.
Bundle protection remains [A] pending live proof; the merge hook is optional and off.
Status inspects structural installation; activation remains unverified
until the runtime invokes it. Project trust, exact-hook review, disabled hooks,
administrator policy and runtime support may prevent activation. Adoption grants
no trust or permissions. Context, fetch and push still require explicit actions;
no SessionStart/PostToolUse/SessionEnd automation is installed.

Least-privilege Codex permissions (sandbox profile, narrowed rules, merge limits) are a
document TiesL applies by hand: see `.guardrails/source/adapters/codex/permission-baseline.md`
(in the SDG repo itself: `adapters/codex/permission-baseline.md`).

Before dependent work, run `.guardrails/source/adopt.sh --runtime codex --status .`
from the project checkout. Surface each `stale/broken/missing: .agents/skills/<name>`
line with the remedy: rerun ordinary Codex adoption (`adopt.sh --runtime codex`).
If status is unavailable or nonzero, report the gap or printed diagnostics and
continue the session. A nonzero status can indicate structural drift; it does not
establish live skill discovery or current-session loading. Never repair, create
or remove paths from this instruction; `adopt.sh` remains the sole owner of
repair, refresh and removal. This read-only check installs no hook and writes no
Codex config or trust. Newly linked skills may require a fresh session.
The status check is not mechanically enforced: instruction suppression or
noncompliance (parent/deeper instructions, AGENTS.override.md, instruction budget,
model choice) can prevent it. Remote/cloud sessions remain unverified. Live
CLI/local desktop behavior and discovery after the remedy are separate manual
observations, unverified until observed.

Before dependent work, run and read `.guardrails/source/session-context.sh --runtime codex <project>`
from the project checkout (use `.` for <project>). Read each invoked skill's
SKILL.md through `.agents/skills/<name>/SKILL.md` before following it. These are
individual links to canonical skills, including grilling and role-contracts;
CLI and desktop share the same installation. A Markdown link is not an import.
Resolve clone commands and the canonical skills' existing path examples by
setting `SPEC_DRIVEN_GUARDRAILS_DIR` to the physical local `.guardrails/source`
checkout for this session. A `.claude/skills/<name>` example in shared skill
content maps to `.agents/skills/<name>` here; do not create Claude files.
Claude-only frontmatter such as context/allowed-tools is runtime metadata,
not evidence of Codex dispatch or enforcement. If supported-version skill
metadata/discovery fails, stop and return to Architect; never duplicate bodies.

When process-multi-agent-roles is yes, read and follow canonical
`.agents/skills/role-contracts/ORCHESTRATOR.md` from session-context output.
Once authorized, continue ordinary stage handoffs and finding routes with
available fresh role dispatch without requesting confirmation for each handoff.
Follow that owner's scopes, records, route tables, human override and merge
confirmation rules; no Codex-specific policy replaces them. If required fresh
dispatch is unavailable or fails, stop that stage and request the existing
human stop/override decision, never collapse roles or infer consent from silence.
Resume using durable issue/PR artifacts, stage markers, Pipeline log and open
findings; follow the canonical next-stage or finding route rather than treating
initial-stage completion as completion of a later route. Separate comments do
not establish fresh sessions. Continuation is instruction-driven; installation
and static checks cannot prove live autonomy, session freshness or obedience.

Run `.guardrails/source/merge-preflight.sh <n>` from the project checkout before
`gh pr merge`, with the PR number as `<n>`, and do not merge on a non-zero exit. It feeds the same
`hooks/git-guardrails` that Claude's hook runs (up-to-date, review marker, CI,
role-play checks). This is instruction-driven, not interception: the preflight
is not a hook and nothing makes a session run it. Without explicit --hooks
opt-in, runtime-hooks stays not-installed; the optional hook intercepts Bash
merge attempts only and does not replace this preflight requirement.

Dispatch mapping: `SendMessage` and `fork` in the canonical rules are Claude
tool names. Read `SendMessage` as Codex's continue-an-agent tool and `fork` as
any spawn that inherits context; the rules apply unchanged. If the platform
reports no token or tool count for a subagent, log `tokens=n/a tools=n/a`,
treat the size as unknown, which OR13 resolves to a fresh dispatch, and never
estimate. The transcript extraction command in `dispatch-economy` is
Claude-only.

Start a fresh CLI/desktop session after adoption/update and observe actual
loading: global/parent and deeper instructions, AGENTS.override.md precedence
and the combined instruction budget can suppress rules. Adoption does not
change Codex config.toml, trust, permissions, unrelated user hooks or plugins. Withheld trust
and unsupported versions must be recorded as unavailable, not observed success.

Shared native pre-commit/commit-msg/pre-push hooks and configured CI checks retain
coverage limits: foreign hooks, hooksPath, --no-verify, missing dependencies and
escape hatches. Native hooks do not intercept `gh pr merge`; merge into main
still needs explicit human confirmation, the canonical review evidence and a
clean merge-preflight.sh run.
Codex specialized/indirect shell actions remain outside Bash hook interception.
Read-only status establishes structural installation, never live loading.

The completion instructions below describe the default installation without
`--hooks`. With `--hooks`, the optional Bash merge hook intercepts merge
attempts, but does not give the completion reminder or reset context.

## Completion and fresh context

Before merging, save the PR number and repository plus base/head identity before
branch deletion. After the completed merge, confirm `state == MERGED` using that
saved number/repository. Queued `--auto` is insufficient. Use the actual completed
tool result for merge success; failed or uncertain results give no reminder.
Finish durable reporting before the merge. This is instruction following, with no
runtime hook enforcement or automatic context clearing; runtime-hooks stays
not-installed.

After a confirmed merge into main, from any head, give the reminder in your
response: CLI — "Merged to main. Use /clear or /new before the next work item; if
you are tagging a release, tag it first." Desktop — "Merged to main. Start a New
chat before the next work item; if you are tagging a release, tag it first." If
the surface is unknown, give both labeled actions. The reminder is not a stop;
continue any remaining requested work. Tag commands and publication give no
reminder. CLI `/clear` and `/new` start fresh chats after the current task ends;
a shell terminal clear does not. Desktop New chat is `Cmd+N` on macOS or `Ctrl+N`
on Windows/Linux. Reset remains maintainer-owned. A merge into a release branch
continues without this reminder.
