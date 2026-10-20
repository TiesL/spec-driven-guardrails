## Codex CLI and desktop runtime mapping

The policy above is embedded in the managed AGENTS.md block. Claude-specific
automatic hook statements in that policy apply to Claude's adapter. This Codex
adapter installs no runtime hooks: context, fetch, push and guards require
explicit instruction-following/manual actions plus shared native Git and CI
checks. runtime-hooks: not-installed; runtime shell interception unavailable

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
is not a hook, nothing makes a session run it, and runtime-hooks stays
not-installed.

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
change Codex config, trust, permissions, user hooks or plugins. Withheld trust
and unsupported versions must be recorded as unavailable, not observed success.

Shared native pre-commit/commit-msg/pre-push hooks and configured CI checks retain
coverage limits: foreign hooks, hooksPath, --no-verify, missing dependencies and
escape hatches. Native hooks do not intercept `gh pr merge`; merge into main
still needs explicit human confirmation, the canonical review evidence and a
clean merge-preflight.sh run.
Codex specialized/indirect shell actions have no adapter runtime interception.
Read-only status establishes structural installation, never live loading.

## Completion and fresh context

Before merging, save the PR number and repository plus base/head identity before
branch deletion. After the completed merge, confirm `state == MERGED` using that
saved number/repository. Queued `--auto` is insufficient. Use the actual completed
tool result for publication success; failed or uncertain results do not claim
successful completion. Follow the shared distinct tool call and durable reporting
ordering above. This is instruction following, with no runtime hook enforcement
or automatic context clearing; runtime-hooks stays not-installed.

After a non-release main merge end the turn with: CLI — "Merged to main. Use
/clear or /new before the next work item." Desktop — "Merged to main. Start a
New chat before the next work item." After tag publication substitute "Tag
published." for "Merged to main." If the surface is unknown, give both labeled
actions. CLI `/clear` and `/new` start fresh chats after the current task ends;
a shell terminal clear does not. Desktop New chat is `Cmd+N` on macOS or `Ctrl+N`
on Windows/Linux. Reset remains maintainer-owned. A release-head merge into main
allows only the approved tag next, then the same final stop/prompt; a merge into
a release branch continues without this prompt.
