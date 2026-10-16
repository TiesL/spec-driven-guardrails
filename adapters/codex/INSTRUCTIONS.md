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

Start a fresh CLI/desktop session after adoption/update and observe actual
loading: global/parent and deeper instructions, AGENTS.override.md precedence
and the combined instruction budget can suppress rules. Adoption does not
change Codex config, trust, permissions, user hooks or plugins. Withheld trust
and unsupported versions must be recorded as unavailable, not observed success.

Shared native pre-commit/commit-msg/pre-push hooks and configured CI checks retain
coverage limits: foreign hooks, hooksPath, --no-verify, missing dependencies and
escape hatches. Native hooks do not intercept `gh pr merge`; merge into main
still needs explicit human confirmation and the canonical review evidence.
Codex specialized/indirect shell actions have no adapter runtime interception.
Read-only status establishes structural installation, never live loading.
