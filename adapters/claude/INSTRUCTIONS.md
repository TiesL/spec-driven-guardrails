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

The synchronous Bash PostToolUse `stop-after-completion` hook prints "Merged to
main. Type /clear before the next work item; if you are tagging a release, tag
it first." as a `systemMessage` after every successful merge into `main`, release
heads included, and does not stop the session; tag commands give no reminder.
It uses a bounded PR lookup; failed/uncertain lookup is advisory and fails open.
The canonical `gh pr merge <n> --squash --delete-branch` names the PR. An
omitted target is resolved from the current branch, or, after `--delete-branch`
switched to main, from the checkout reflog (including gh's fast-forward pull after the
checkout) when that branch is gone and the lookup's head matches; other omitted forms fail open. Output
redirections (`2>&1`, `>file`) keep the proof; pipes and input redirections do
not. Commands batched into the same Bash call are unaffected.
It cannot run `/clear` or reset context. Script tests establish wiring and output;
live hook loading, display of the reminder and `/clear` require a Claude session.
