# #430 acceptance evidence — release head `3ffa08b`

The corpus check used the release-head `rec_scan_bundle` over all issue and PR
bodies, issue/PR comments, and PR review bodies readable through GitHub REST.
The final scan was after creating the scratch dry-run and synthetic histories.
No private body text is reproduced here.

| Adopter | Roles opted in | Bodies | model-record ok / near-miss / quoted | pipeline-override ok / near-miss / quoted | Inline rows |
| --- | --- | ---: | --- | --- | ---: |
| spec-driven-guardrails | yes | 1291 | 570 / 0 / 50 | 1 / 0 / 1 | 0 |
| tennis-invoicing | yes | 79 | 37 / 0 / 0 | 2 / 0 / 0 | 0 |
| sdg-dryrun-scratch | yes | 47 | 19 / 11 / 0 | 0 / 0 / 0 | 5 |
| tennis-admin | no | 44 | 0 / 0 / 0 | 0 / 0 / 0 | 0 |
| tennis-registration | no | 25 | 0 / 0 / 0 | 0 / 0 / 0 | 0 |
| agentic-workflow-installer | no | 26 | 3 / 0 / 0 | 0 / 0 / 0 | 0 |
| portfolio-mgt-agents (Ties-IT-advies) | no | 37 | 5 / 0 / 0 | 0 / 0 / 0 | 0 |

The six earlier scratch near misses have an unquoted model. The five new inline
near misses are synthetic: [Discovery](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132450170),
[Planning](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132450453),
[Test](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132450696),
[Implementation](https://github.com/TiesL/sdg-dryrun-scratch/issues/13#issuecomment-6132451072),
and [Review](https://github.com/TiesL/sdg-dryrun-scratch/pull/14#issuecomment-6132451358).
The collector on [inline-only PR #14](https://github.com/TiesL/sdg-dryrun-scratch/pull/14)
reported gate 1 `indeterminate` and gate 2 `indeterminate`; the release gate
reported all five candidates as near misses and `role-played: stages missing:
Discovery, Planning, Test, Implementation, Review`.

Open opted-in PRs with a changed blocking verdict versus v0.3.0:
[scratch #5](https://github.com/TiesL/sdg-dryrun-scratch/pull/5) and
[scratch #14](https://github.com/TiesL/sdg-dryrun-scratch/pull/14) had only
non-blocking model warnings under v0.3.0; the release gate refuses them for
missing stages. [Scratch #10](https://github.com/TiesL/sdg-dryrun-scratch/pull/10)
has a non-blocking verdict under both gates: v0.3.0 flags its five markers for
missing effort, while the release gate prints nothing. Scratch #3 and #7 have
the same verdict under both; there are no open PRs in the other opted-in
adopters. No repository readable in the owner's account or the
Ties-IT-advies organization with WORKFLOW-ADOPTION.md was unverified.
Adopters outside those accounts cannot be seen and remain unverified by
construction. The check uses the same reader it tests and shares its blind
spots.

## AC2 dry run

Setup: guardrails checkout SHA `3ffa08b36eee99a34bb4cdcc3747035eaf5b3ddd`
equals `origin/release/408-process-improvements`; the scratch clone was
re-adopted from that checkout. A fresh Claude Code session resumed [issue
#8](https://github.com/TiesL/sdg-dryrun-scratch/issues/8) at Implementation
and dispatched a Developer and a fresh Reviewer. Two earlier attempts halted
on noninteractive command permissions and changed no committed work. The
successful run opened [PR #10](https://github.com/TiesL/sdg-dryrun-scratch/pull/10)
at `267b6e19762d2491df0b578437109e3b92c37986`; it remains open.
Its test report says 18 passed, 0 failed; no independent CI exists on this
scratch repository.

All five stage records on issue #8/PR #10 classify as `ok`, with no near miss
or quoted record. The release gate printed no line (exit 0). The collector
reported gate 1 `evidenced` and gate 2 `unverifiable-from-artifacts` because
Implementation used Haiku 5.5 and Review used Sonnet 5.5. Its quality-review
gate was `evidenced`; CI was `not-evidenced`. Seven Agent dispatch prompts
across the dry-run stream transcripts were checked, and none contains
`--effort`.

## AC3 warning visibility

The fake gh consumed its fail-once flag on the gate's PR reviews fetch while
Claude attempted `gh pr merge 10`. The fake gh refused the final merge, so
PR #10 stayed open. With `--include-hook-events`, the `PreToolUse:Bash`
hook event contained:

```
warning: merge-guard role-play check was unchecked:
role-play-unchecked: couldn't consult PR #10's reviews
```

Claude's tool result contained only `fake gh: merge suppressed for #430
acceptance`, and its final answer said no merge-guard warning was shown. Thus
the warning is visible in the stream transcript's hook event but did not
reach the agent as command output in this run. A34's statement that the hook
prints the warning is observed; this run does not establish delivery to the
agent. The merge guard also printed a no-CI warning in the hook event.
