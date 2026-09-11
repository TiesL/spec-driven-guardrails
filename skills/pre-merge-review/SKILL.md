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

**How it runs.** `context: fork` provides fresh, isolated context — no "I
just built this and it works" in the context. The model is deliberately
not pinned in the frontmatter — see **Model choice** below. `allowed-tools`
excludes `Edit`/`Write`/`NotebookEdit`: this skill cannot modify the
working tree with an editor tool. `Bash` *is* allowed (needed for
`scope.sh`, `gh pr diff`, posting the findings comment) and is therefore
not a technically enforced write ban — use it only to read and to post the
comment, never to change files. This skill delivers findings, not fixes.

## Model choice

No fixed model — that wouldn't account for what the PR actually calls
for, and Ties deliberately wants to vary model use rather than reflexively
reaching for the heaviest model every time. Choose, per invocation, a
model that is **at least as skilled as the model that wrote the reviewed
change**, and, within that floor, the most cost-effective. A simple change
by a light model may be reviewed by a light model; a change by a heavy
model never deserves a lighter reviewer.

If the chosen model deviates from what's obvious, make that visible — in
the PR or the findings comment — so a later reader can see which model
reviewed and why. The rest of this procedure (isolated context,
`scope.sh`, `scenario-poort.sh`, the marker) doesn't change with the model
choice: that's a separate knob, not a package deal — a different model
choice is no license to also skip the rest of the procedure.

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
.claude/skills/pre-merge-review/scenario-poort.sh .
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

## Substantiation gap as a finding

If the PR touches a topic whose scope line carries `[requires
substantiation]`, that is itself an explicit finding in the PR: the
corresponding `WORKFLOW-ADOPTION.md` row must get a real answer before the
merge (see the `adoption-registry` skill) — this is the first gate of the
phased substantiation requirement (F6).

## The marker

Post, in the findings comment on the PR, on its own line, literally:

```
<!-- pre-merge-review:done -->
```

Machine-recognizable and fixed — never paraphrase. The merge guard (F8,
W10b) looks for this later.

## What happens with it

The findings go into the PR itself, not only in the chat: readable,
persistent, findable afterward. Every finding is then either resolved, or
recorded under *Technical debt* in the PRD with a reason. Nothing
disappears silently.

## Its limits

Models share a lot of training data, so even a different model has partly
overlapping blind spots. This raises the floor; it doesn't replace an
experienced engineer looking with different eyes.
