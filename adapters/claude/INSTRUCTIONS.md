## Claude Code runtime mapping

Claude reads this generated WORKFLOW.md through the project's CLAUDE.md link.
Read applicable `session-context.sh --runtime claude <project>` output before
workflow-dependent work and read each invoked canonical skill's SKILL.md before
following it. Skills are installed under `.claude/skills/`. Resolve workflow
scripts through `$SPEC_DRIVEN_GUARDRAILS_DIR`; canonical skills remain in `skills/`.

The automatic SessionStart fetch/context, Bash PreToolUse guard,
PostToolUse push-after-commit and SessionEnd push statements above describe
Claude's installed `settings/session-hooks.json`. Existing non-Bash/indirect
bypasses, missing gh/network/readers, fail-open warnings, post-action failure
notices and branch exceptions still apply. Native Git hooks and CI supplement
those hooks; foreign hooks, hooksPath, --no-verify, missing dependencies and
escape hatches limit coverage. Neither native Git hooks nor CI intercept
`gh pr merge`. CI checks artifacts, not authorship, freshness or obedience.
