---
name: pre-merge-review
description: >
  How the quality review before a merge runs: fresh context, a model at
  least as skilled as whoever wrote the code, scope proportional to the
  PR, findings in the PR itself. Use this before merging a PR, or when
  someone asks how the quality review works.
context: fork
allowed-tools: Read, Grep, Glob, Bash
---

## Quality review before the merge

Ties can't fully assess the technical output himself. The review must
therefore produce *readable evidence* instead of reassurance.

**When this runs.** As soon as the PR is open (or as soon as a push
settles) — immediately, in parallel with CI, not gated on CI's status.
Don't skip straight to asking for merge confirmation without having run
this first; the merge guard (`git-guardrails`, `gh pr merge`) blocks an
unreviewed merge regardless, so skipping this step only costs a round
trip. This used to wait for CI to go green first, specifically because an
earlier review could otherwise go stale (see "The marker" below) — since
the marker is now pinned to the commit it reviewed (issue #225), a commit
that lands after review (a fixup, or a fix for a red CI) simply requires a
fresh review, whenever it ran. There's no longer a reason to wait: CI and
review both start immediately and run alongside each other, and the merge
guard separately still requires CI to be green regardless of the review's
own timing.

**How it runs.** `context: fork` provides fresh, isolated context — no "I
just built this and it works" in the context. The model is deliberately
not pinned in the frontmatter — see **Model choice** below. `allowed-tools`
excludes `Edit`/`Write`/`NotebookEdit`: this skill cannot modify the
working tree with an editor tool. `Bash` *is* allowed (needed for
`scope.sh`, `gh pr diff`, posting the findings comment) and is therefore
not a technically enforced write ban — use it only to read and to post the
comment, never to change files. This skill delivers findings, not fixes.

## Model choice

See the `model-choice` skill for the canonical principle (floor + cost,
stated qualitatively, never a model name) and how it applies across every
pipeline stage. This review is that skill's Review-stage instance: choose
a model **at least as skilled as the model that wrote the reviewed
change**, and, within that floor, the most cost-effective. Record which
model reviewed — always, not only when it deviates from what's obvious —
as a `<!-- model-record: stage=Review model="..." effort="..." -->`
marker (see `model-choice`'s "Machine-readable form"), not just prose.

Run `skills/pre-merge-review/model-record-gate.sh <pr-number>` to check
that every stage — not only this one — has a matching marker somewhere in
the PR or the issue(s) it closes. A missing stage is a finding, the same
non-blocking shape as every other gate here.

The rest of this procedure (isolated context, `scope.sh`,
`scenario-gate.sh`, the marker) doesn't change with the model choice:
that's a separate knob, not a package deal — a different model choice is
no license to also skip the rest of the procedure.

## The scope

**Always**, regardless of which NFRs this project chose: complexity (is
this the simplest form that works?) and dependencies (is a new dependency
needed, maintained, safe?) — basic hygiene, not optional.

**On top of that**: exactly the NFRs whose corresponding `spec-*` question
was answered `yes` for this project (`WORKFLOW-ADOPTION.md`) — nothing gets
reviewed against a specification it isn't even part of.

Don't compute that scope by hand — run:

```
.claude/skills/pre-merge-review/scope.sh .
```

That prints, one per line: `complexity`, `dependencies`, and then per
answered NFR `<id>: <heading name>` — where `<heading name>` is the `###`
section in `PRD.md` matching the generated anchor (`<!-- nfr: <id> -->`,
from F4). If that anchor is missing, the script falls back to the heading
name from `spec-driven-guardrails`'s `nfr/` register and reports that on
stderr — a project without anchors doesn't block the review, it degrades.

An NFR line ending in `[requires substantiation]` means: that
`WORKFLOW-ADOPTION.md` row still carries the provisional stamp from F6, not
a real "yes". Treat that as a review finding (see below) — not as an
ordinary scope line to review.

Reading the diff itself is delegated to the existing `code-review` skill,
with this scope as input.

## The PR gate (links 2 and 3, W20)

Besides the NFR scope above, this skill also checks the traceability chain
toward issues, using `gh` and network access it already needs anyway:

**Link 2 — is every scenario named by an issue?** Run:

```
.claude/skills/pre-merge-review/scenario-gate.sh .
```

That prints, one per line, every scenario ID from `TEST-SCENARIOS.md` that
is named by no issue in its `**Covers:**` field. Only that field counts —
an ID that happens to appear in a sentence (e.g. "we've already tested
some s1 variants") is not a reference. Every reported line is a finding.

**Link 3 — does *this* PR reference an issue?** One call:

```
gh pr view --json closingIssuesReferences --jq '.closingIssuesReferences | length'
```

If that's `0`, that's a finding: the PR is missing `Closes #<issue>` or a
linked issue. The same check exists as a hard block in CI (W19b,
`check-pr-issue-link.sh`) — this skill additionally runs it before the
merge, with the finding in the PR itself.

Both checks fail open without `gh` or network: a warning, not a block —
the same ground rule as deploy-guards and the merge guard (W10b).

## Adoption postcondition gate (#239)

Filesystem-only, no `gh`/network needed, so nothing to fail open on. Run:

```
.claude/skills/pre-merge-review/adoption-postcondition-gate.sh .
```

That checks whether a `WORKFLOW-ADOPTION.md` row answered `yes` actually
holds — scoped to the two rows found broken in practice (#238's
`portfolio-mgt-agents` audit): `traceability-link-1` answered yes with no
`check-traceability.sh` present or wired into the project's own `check`;
`ci-gate-on-merge` answered yes with no CI workflow that calls `check` at
all. Every reported line is a finding, the same as links 2 and 3 above. A
row answered `no` (including "no — not yet", see #239 AC3) is never
checked — it never claimed the postcondition holds in the first place.

## Pending adoption gate (#240)

`pending-changes.sh` already detects every applicable `CHANGES.md` row with
no answer yet in `WORKFLOW-ADOPTION.md` — but until now it only ran from
the `SessionStart` hook, a single notice easy to scroll past mid-session
and never re-surfaced at PR time. Found via #238 (`portfolio-mgt-agents`):
8 applicable rows sat unanswered and unmentioned across two merged PRs.

Run it the same way the `SessionStart` hook resolves its own checkout path:

```
p="$(pwd)"; target=$(readlink "$p/.claude/settings.json" 2>/dev/null); \
  wf=$(dirname "$(dirname "$target")"); \
  [ -x "$wf/pending-changes.sh" ] && "$wf/pending-changes.sh" "$p"
```

Any output is a finding in the PR, one row per line — not a hard block
(same fail-open philosophy as everything else here): a pending row is a
question to put to Ties, not a reason by itself to refuse the merge.

## Substantiation gap as a finding

If the PR touches a topic whose scope line carries `[requires
substantiation]`, that is itself an explicit finding in the PR: the
corresponding `WORKFLOW-ADOPTION.md` row must get a real answer before the
merge (see the `adoption-registry` skill) — this is the first gate of the
phased substantiation requirement (F6).

## The marker

Post, in the findings comment on the PR, on its own line:

```
<!-- pre-merge-review:done sha=<full 40-character commit SHA> -->
```

Fetch the PR's current HEAD SHA — `gh pr view --json headRefOid --jq
.headRefOid` — and substitute it in. Never paraphrase the fixed
`<!-- pre-merge-review:done sha=... -->` shape. The merge guard (F8, W10b)
requires this marker's SHA to match the PR's *current* HEAD when `gh pr
merge` is called (issue #225) — a marker for an older commit doesn't
count, the same as no marker at all. That's deliberate: it's what makes it
safe to run this review before CI finishes (see "When this runs" above)
instead of waiting for it — a fix commit that lands afterward, for
whatever reason, automatically needs a fresh review.

## What happens with it

The findings go into the PR itself, not only in the chat: readable,
persistent, findable afterward. Every finding is then either resolved, or
recorded under *Technical debt* in the PRD with a reason. Nothing
disappears silently.

**Machine-readable disposition, per finding (#241 AC2).** "Nothing
disappears silently" used to rest entirely on the next round remembering
— fresh context means it doesn't remember. Found via #238
(`portfolio-mgt-agents` PR #4): round 1 flagged a missing Decision Log
entry, round 2 ran fresh-context and never carried it forward, the PR
merged 17 seconds later. Every individual finding now carries its own
marker, immediately after that finding's text:

```
<!-- finding:<short-slug> status=open -->
<!-- finding:<short-slug> status=resolved -->
```

On a second (or later) round, run
`skills/pre-merge-review/finding-carryforward-gate.sh <pr-number>` before
posting — it compares the two most recent `pre-merge-review:done`
comments and reports any slug the previous round left `status=open` that
doesn't reappear (open or resolved) in this round's comment. Every such
report is itself a finding: re-flag it or explicitly resolve it, don't let
it just vanish.

## Its limits

Models share a lot of training data, so even a different model has partly
overlapping blind spots. This raises the floor; it doesn't replace an
experienced engineer looking with different eyes.
