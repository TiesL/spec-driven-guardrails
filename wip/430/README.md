# #430 acceptance evidence tooling (branch `wip/430-acceptance`, never merged)

Evidence is posted on issue #430; this directory only holds what reproduces it.
`W` = `<guardrails clone>/.git/430-work` (untracked work dir).

## Setup
    git fetch origin
    git worktree add --detach $W/release-head origin/release/408-process-improvements
    git worktree add --detach $W/v0.3.0 v0.3.0
    git clone git@github.com:TiesL/sdg-dryrun-scratch.git ~/Documents/ClaudeCodeZandbak/sdg-dryrun-scratch-430
    SPEC_DRIVEN_GUARDRAILS_DIR=$W/release-head $W/release-head/adopt.sh ~/Documents/ClaudeCodeZandbak/sdg-dryrun-scratch-430
The dry-run clone must sit outside any `.git/` directory: Claude Code refuses
Write/Edit under `.git/` paths (run 1 stopped at Implementation on that). A
second scratch clone at `$W/sdg-dryrun-scratch` was used only for the
read-only gate comparison.
Setup check (AC2): `git -C $W/release-head rev-parse HEAD` equals `origin/release/408-process-improvements`.

Run git commits for this branch from the guardrails clone's own directory: the
git-guardrails hook judges the shell's working directory, and the scratch
clone sits on `main`.

## AC1 corpus check
    wip/430/corpus-check.sh $W/release-head $W/corpus <owner/repo>...
Open-PR verdict change: from a clone of each opted-in adopter, run
`$W/release-head/skills/pre-merge-review/model-record-gate.sh <pr>` and
`$W/v0.3.0/skills/pre-merge-review/model-record-gate.sh <pr>` and compare.

## AC2 dry run
Fresh headless sessions in `~/Documents/ClaudeCodeZandbak/sdg-dryrun-scratch-430`, with
`SPEC_DRIVEN_GUARDRAILS_DIR=$W/release-head`, plain prompts that do not mention
the pipeline; then the gate and `compliance-evidence.sh` on the resulting PR.

## AC3 warning visibility
`wip/430/fake-gh/gh` fails the merge guard's gate `/reviews` fetch once when
`FAKE_GH_FLAG` names an existing file. Run the merge session with
`PATH=<guardrails>/wip/430/fake-gh:$PATH FAKE_GH_FLAG=$W/fakegh.flag` after
`touch $W/fakegh.flag`, with `--output-format stream-json --verbose` so the
transcript shows whether the `role-play-unchecked:` warning reached the session.
The real gh path is hard-coded for this machine.
The fake gh also refuses the final `gh pr merge` command, keeping the reviewed
scratch PR open after the guard has run. Use `--include-hook-events` to capture
the guard's stderr even when Claude does not receive it as command output.

`inline-only-fixture.py` posts five deliberately invalid inline candidates to
a scratch issue and PR. Run it only once per fixture: each invocation posts new
comments.
