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

TiesL can't fully assess the technical output himself. The review must
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
comment, never to change files. This skill delivers findings, not fixes: a finding names the defect, its class (`design`, `code`, `test` or `spec`) and a falsifying check, and never gives a fix or a patch (`role-contracts`, "Reporting a defect or finding").

Every Review round, including a re-review after a fix commit, is a new dispatch of a fresh Reviewer; a Reviewer is never continued, by `SendMessage` or by the dispatch tool's `fork` type (not the `context: fork` above).

## Review depth: quick vs thorough

Every PR gets at least the single isolated Reviewer run above (`context: fork`) —
"quick" mode, unchanged. On top of that, run:

```
"$SPEC_DRIVEN_GUARDRAILS_DIR/classify-review-depth.sh" <pr-number>
```

That prints exactly one line: `review-depth: quick`, or `review-depth:
thorough (<matched categories, or "forced"/"lookup-failed">)`. It
classifies by matching the PR's changed-file paths and its own title+body
against Reviewer's existing six security-review trigger categories
(above) — no new taxonomy, no size/files-touched dimension (A13 in
`wip/multi-agent-development/ARCHITECTURE-MULTI-AGENT-WIP.md` explicitly
rejected the latter). Pass `--force-thorough` to opt a specific real PR
into thorough mode regardless of what the categories say — a manual
override for dogfooding this mechanism before issue #307 decides on any
default-on rule, never a standing default itself.

**When the verdict is `thorough`:** run the Reviewer as usual, **plus
exactly `LENS_ADAPTER_COUNT` additional lens-Adapter runs** — fresh,
isolated `context: fork` instances, generic and undifferentiated copies
of Reviewer's own review scope (same prompt, same finding format, same
`allowed-tools`), never named personas (no "Blind Hunter", no "Edge Cases
Hunter"), and never one adapter per matched trigger category — the count
is a small fixed constant, not derived from how many categories matched.
Read the actual number by running:

```
"$SPEC_DRIVEN_GUARDRAILS_DIR/classify-review-depth.sh" --lens-adapter-count
```

rather than restating the literal number here — `classify-review-depth.sh`
defines `LENS_ADAPTER_COUNT` in exactly one place, and this prose reads it
from there so a future edit to either side that lets the two drift apart
shows up as a mismatch (a lens-Adapter dispatch count that no longer
matches what the script reports), not a silent one. Every lens-Adapter's
findings go into the same PR findings comment as Reviewer's own, under
the same machine-readable disposition convention ("What happens with it"
below) — a second or third set of eyes, not a second gate with its own
marker.

**When the verdict is `quick`:** nothing changes — the single isolated
Reviewer run above is the whole review, same as before this classifier existed.

Both `classify-review-depth.sh` and `--lens-adapter-count` fail open the
same way every other `gh`-dependent check in this skill does when `gh` or
network isn't available — see the script's own header for the exact
fail-open direction (toward `thorough`, the inverse of this repo's usual
default, since under-reviewing a security-shaped change on missing
evidence is the wrong way to guess).

## Model choice

See the `model-choice` skill for the canonical principle (floor + cost,
stated qualitatively, never a model name) and how it applies across every
pipeline stage. This review is that skill's Review-stage instance: choose
a model that is **at least as capable as the model that did
Implementation** (#392). A different model is not required, and a legacy
`same-model-exception` is ignored. Within that floor, the cheapest model
that clears it. The floor is judged on the model alone: effort is neither
chosen nor checked (#424; the limit is stated in `model-choice`). Record
which model reviewed, always, not only when it deviates from what's obvious, as a
Review marker with `floor-basis`. Produce it with
`.claude/skills/pre-merge-review/model-record-emit.sh --stage Review --model <your
exact model id> --floor-basis '<sentence>'` and paste the output unchanged; never
type a marker by hand. Run it from the project root: the path goes through
the project's installed skill (the guardrails repo installs its own skills
the same way). `floor-basis` is required on every Review marker:
one sentence on why this model clears Implementation's. The format and its
grammar are owned by `model-choice` ("Machine-readable form", "Marker
grammar"). The gate checks that `floor-basis` is present, never what it
says.

Run `skills/pre-merge-review/model-record-gate.sh <pr-number>` to check
that every stage — not only this one — has a matching marker somewhere in
the PR or the issue(s) it closes. A missing stage is a finding, the same
non-blocking shape as every other gate here. The gate also flags a
Review marker without `floor-basis`. It can't rank two different models,
so for those the capability ordering stays your recorded judgment.

In a project that answers `process-multi-agent-roles` yes, the gate also
prints a `role-played: ` line when one session played the pipeline's roles
instead of dispatching them: one comment, review or PR description carries
markers for two or more different stages, or a stage has no marker at all.
That finding blocks: give a request-changes verdict, and the merge guard
refuses `gh pr merge` on it by itself, so posting the approval marker
doesn't get it through. Only a human decision recorded on the issue or PR
as a live `pipeline-override` marker (`scope="single-session"` or
`scope="skip=<Stage>"`, with `decided-by` and `reason`; see the
`role-contracts` skill's `ORCHESTRATOR.md`) waives it. Without `gh` or
network the gate and the guard let the merge through, as every gate here
does.

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

**Link 3 — does *this* PR reference an issue?** Run the actual script CI
uses (#323 — don't hand-roll a `gh pr view --json closingIssuesReferences`
one-liner: that call is GraphQL-backed and 403s from inside a Claude Code
session, and even outside that block, `closingIssuesReferences` is only
populated by GitHub when the PR's base is the repository's *default*
branch, so it's silently empty for every PR into a release branch):

```
templates/check-pr-issue-link.sh <pr-number>
```

It checks two paths, in order: `closingIssuesReferences` first (covers
the default-branch case, and any non-default-branch PR with a manually
linked issue in its Development sidebar), then — only when that's empty
and the base isn't the default branch — a direct closing-keyword scan
against the PR's own title+body. A finding is exit `1` with a message on
stderr (the script has no fail-open path of its own: an infra failure
that stops it from consulting the PR is itself reported as the finding,
same as a genuinely missing reference). The same check exists as a hard
block in CI (W19b) — this skill additionally runs it before the merge,
with the finding in the PR itself.

**Link 4 — does the issue itself have the structure the other three links
assume (#242)?** Run:

```
.claude/skills/pre-merge-review/issue-structure-gate.sh <pr-number>
```

For every issue the PR closes: a work item with no `### AC<n>` heading or
no `**Covers:**` field is a finding (one per missing piece); an epic whose
Work items list has no real `#<n>` entry (only the unfilled template
placeholder) is a finding. Found via #238: `portfolio-mgt-agents` had zero
issues with any of this structure, and links 1-3 never checked for it —
they check PRD↔scenario, scenario↔issue, and PR↔issue, never the issue's
own shape.

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
question to put to TiesL, not a reason by itself to refuse the merge.

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

The previous round's findings are inputs the new Reviewer re-checks against the new head, not memory: each open slug is verified again, never assumed from a remembered conversation.

On a second (or later) round, run
`skills/pre-merge-review/finding-carryforward-gate.sh <pr-number>` before
posting — it compares every Review round (a PR comment or a PR review,
request-changes rounds included, as `review-rounds.sh` counts them) with the
one before it and reports any slug a round left `status=open` that doesn't
reappear (open or resolved) in the next. Each line names the round that
dropped the slug, as `(round <k>)`. Every such report is itself a finding:
re-flag it or explicitly resolve it, don't let it just vanish. The line goes
away once a later round re-flags the slug or resolves it explicitly.

## Its limits

Models share a lot of training data, so even a different model has partly
overlapping blind spots. This raises the floor; it doesn't replace an
experienced engineer looking with different eyes.
