---
name: merge-risk-panel
description: PROPOSAL (#646, A58), inert by default. Merge into `main` without a per-PR approval, by a 5-0 panel, a read-only verifier, a timed hold and one executor. Applies only in a repository whose accepted `main` holds `policy/merge-autonomy.json` with `"enabled": true`, an `acceptance` link and this repository's name; everywhere else, every adopted project included, it is inert and the normal approval rule holds. Use when an orchestrator considers a `main`-bound work-item merge under that delegation.
---

# Merge-risk panel

Status: PROPOSAL for the maintainer (#646, design A58). Nothing here takes
effect without his recorded acceptance; silence accepts nothing. The skill is
procedure; `policy/merge-autonomy.json` is the data; `merge-risk-evidence.sh`
(with private `lib/merge-risk.py`) is the only reader of both.

## Applicability

This skill applies only when the configuration at the current `main` tip has
`"enabled": true`, an `acceptance` link to the maintainer's comment on #646 and
`repository` equal to this repository. Otherwise it is inert: in an adopted
project, or with the shipped file (`enabled: false`, `acceptance: null`,
`executor_host: ""`), every merge into `main` keeps WORKFLOW.md step 4 / OR11.
The verifier answers `autonomy-disabled` (referred) for every PR then.

## Hard gates

Gates come first and are never votes. Both scripts live in the guardrails
checkout; below, their bare names mean these paths.
`"$SPEC_DRIVEN_GUARDRAILS_DIR/merge-risk-evidence.sh" --phase class <n>` runs
`"$SPEC_DRIVEN_GUARDRAILS_DIR/merge-preflight.sh" <n>` with `CLAUDE_WORKFLOW_MERGE_GUARD_OFF` and
`CLAUDE_WORKFLOW_GUARDRAILS_OFF` removed; a non-zero exit or any `warning:` line
fails it. The required check `check` must be completed `SUCCESS` on H; pending
is `gates-pending`. `--phase final` also needs the Review marker for H. A red,
pending, skipped or unreadable gate means: convene no panel, merge nothing.

The code that judges must be B's code. The executor runs from a dedicated
detached checkout of B (`git worktree add --detach`), refreshed with
`git fetch origin` and `git checkout --detach origin/main` before each item,
and points `SPEC_DRIVEN_GUARDRAILS_DIR` and its session hooks at it. The
verifier compares its own checkout with B: `HEAD` not B, B not in the local
object store, or any reserved file whose working bytes differ from B is
`verifier-not-at-base` (unresolved). After a merge B moves, so the next item
waits until the checkout is refreshed.

## Class and disqualifiers

The class, caps, path groups, reserved paths, labels and release heads are
defined only in `policy/merge-autonomy.json`, read at the `main` tip B, never at
the candidate head; this skill restates no list and no cap. Pattern grammar:
full path, case-sensitive, `*` within one segment, a double star any depth.
Reserved beats every group; a path in no group refers; both counts must be at
least 1 and at most the cap, renames count both paths, measured over B...H.
Also referred: a changed `**Meaning version:**` line in `CHANGES.md`, any review
ever in state `CHANGES_REQUESTED`, a release head, a base other than `main`, not
exactly one closing issue, the off label anywhere. A hold label is `held`.

What the verifier cannot decide is a recorded Reviewer assertion: semantic
disqualifiers (security trade-off, spec-content or authority choice, permission
expansion, weakened protection or oracle, outward-facing action, version or tag
effect, semantic change to this mechanism), accepted-design lineage for guard
paths, baseline lineage for ordinary paths, open medium/high findings.

Verdicts and exit codes: `eligible` 0, `held` 1, `referred` 3, `unresolved` 4,
usage 2; any other exit or a crash is unresolved. Precedence: referred, then
unresolved, then held. Reason codes:
- gates: `gate-preflight`, `gate-preflight-warning`, `gate-escape-hatch`,
  `gates-pending`, `gate-check`, `gate-review-marker`, `verifier-not-at-base`;
- config: `config-absent`, `config-malformed`, `config-invalid`,
  `config-repository`, `autonomy-disabled`, `acceptance-unverified` (detail
  `missing`, `issue` or `author`: the comment must be on #646 of this
  repository, by the repository owner's login);
- class: `pr-not-open`, `base-not-main`, `release-head`, `closing-issues`,
  `behind-base`, `files-unreadable`, `binary-file`, `reserved-path`,
  `unlisted-path`, `cap-files`, `cap-lines`, `diff-unreadable`,
  `meaning-version-line`, `changes-requested`, `issue-unreadable`,
  `labels-unreadable`, `label-off`, `label-hold`, `label-off-control`,
  `control-closed`, `control-unreadable`;
- record: `record-missing`, `record-duplicate`, `record-edited`, `record-label`,
  `record-id`, `manifest-malformed`, `manifest-schema`, `manifest-binding`,
  `identity-head`, `identity-base`, `identity-config-commit`, `identity-diff`,
  `identity-config`, `ac-digest`, `design-digest`;
- rows: `row-not-voter`, `row-duplicate`, `vote-missing`, `vote-dissent`,
  `source-unreadable`, `source-hash`, `position-missing`, `position-duplicate`,
  `position-malformed`, `position-role`, `position-mismatch`, `position-digest`,
  `position-head`, `marker-stage`, `marker-present`, `condition-missing`,
  `condition-scope`, `floor-evidence`, `floor-below`, `assertion`,
  `assertion-missing`;
- hold and execution: `hold-window`, `now-unreadable`,
  `void-after-announcement`, `timeline-unreadable`, `hold-release-missing`,
  `hold-release-target`, `hold-release-words`, `hold-release-stale`,
  `off-since-config`, `config-date-unreadable`, `executor-host-empty`,
  `executor-host-mismatch`; a crash is `verifier-crash`.

## Position line

Five voters: Product, Architect, QA, a fresh Reviewer and the orchestrator.
5-0 only; the Developer never votes; gates never vote. For every `main`-bound
work item the orchestrator puts this duty in each voter's dispatch brief: one
line in the report, then a `conditions:` paragraph whose `paths:` line lists
the patterns the position covers, and what would void it:

    merge-risk-position: role=<Product|Architect|QA|Reviewer|orchestrator> position=<yes-if|yes|no|abstain> ac=<sha256> design=<sha256|pending> head=<H|any>

Product writes `design=pending head=any`; Architect and QA write `head=any`; the
Reviewer writes `position=yes head=<H>` in its Review report; the orchestrator
writes `position=yes head=<H>` in a marker-free issue comment (OR44), sealed
before it reads the Review conclusion. The first line of the four role reports
is their `model-record` marker. A marker alone is never a yes. A report without
a position line is not reused and does not reduce the five: ask the owning role
for a new scoped record, or the maintainer decides. A changed AC, design or
scope routes to the owning role, never to a new vote.

## Manifest and decision record

A is the SHA-256 of the issue body revision current at the acceptance comment's
time; D the SHA-256 of the A-entry in `ARCHITECTURE.md` at a named commit
(`design.source` is `ARCHITECTURE.md@<commit>#A<n>`). Every outcome (eligible,
held, vetoed, unresolved, referred, failed, merged) gets one ordinary comment on
the work-item issue, never only on the PR, and is never edited. The PR
description links it beside `Closes #<work-item>`. Template:

    temporary, panel decision MR-<pr>-<short H>-<n>
    Question: may PR #<pr> merge into main at <H> under the #646 delegation?
    Delegation: <acceptance link>; configuration revision <config_commit>
    Positions: <role>: <position> (<source link>, <sha256>) for all five
    Vote: <k>-<m>, dissent: <role or none>; outcome: <outcome>
    Rationale: <one paragraph>; reservation status: <...>; limit/risk flag: <...>
    T: this comment's created_at; earliest merge: <T + hold_seconds>

    <!-- merge-risk-manifest v1 -->
    ```json
    {"decision_id": "MR-<pr>-<short H>-<n>", "repository": "", "issue": 0,
     "pr": 0, "head": "", "base": "", "diff_sha256": "", "config_sha256": "",
     "config_commit": "", "ac": {"source": "", "sha256": ""},
     "design": {"source": "", "sha256": ""}, "class": [], "reasons": [],
     "authors": [{"model": "", "variant": "", "score": 0, "entry": "", "date": ""}],
     "rows": [{"role": "", "source_url": "", "source_sha256": "", "position": "",
               "model": "", "variant": "", "score": 0, "entry": "", "date": ""}],
     "gates": {"preflight": "", "check_run_id": 0},
     "reviewer_assertions": {"semantic_disqualifiers": "none", "lineage": "",
                             "open_medium_high": "none"},
     "hold_release": null, "outcome": "", "earliest_merge": "", "labels": [],
     "executor_host": "", "queue_key": "", "revert": "pending"}
    ```

The schema is closed. Floor: each voter's Artificial Analysis Intelligence
Index score is at least the highest author's (#645's floor); every entry names
model, variant, score, entry and date. Completion is a new comment linking the
record, with merged H, time, squash SHA S and the exact line `git revert <S>`.
Reversal is a normal maintainer-confirmed revert PR, never autonomous.

Disclosure: merge-risk records are listed in their own 5-0 group; dissent and
unresolved records stay visible; never invent a 3-0 or 2-1 vote.

## Hold

T is the record's server `created_at`; the earliest merge is
T + `hold_seconds`, and `now` is the `Date` header of the verifier's last GitHub
request, never the local clock. A spoken hold (session or relay) becomes the
`hold` label at once, added by the maintainer or a voter; any hold or risk label
vetoes. A hold, risk or off label added at or after T voids the record
(`void-after-announcement`); removal by anyone, or a timer, does not release it.
Any hold, risk or off label ever added to the PR or the work-item issue before
T, even one already removed, needs a release too. Only the maintainer releases
his hold: a record whose `hold_release` quotes his verbatim words about this PR
with their link, dated after the latest such label, then a full new window. No
risk label anywhere is a dormant veto, never evidence of safety.

## Executor sequence

One executor: the orchestrator session on the machine whose `hostname -s` equals
`executor_host`; empty means nothing executes. One PR at a time; log each step in
the Pipeline log:
1. `merge-risk-evidence.sh --phase final <n>`: exit 0, else wait (1) or refer.
2. Queue comment on the control issue:
   `merge-risk-queue: id=<decision_id> pr=<n> head=<H> state=executing host=<host>`.
3. `merge-preflight.sh <n>` fresh: exit 0 without warnings.
4. The literal Bash command
   `gh pr merge <n> --repo TiesL/spec-driven-guardrails --squash --delete-branch --match-head-commit <H>`.
   It must not be wrapped in a script, so the PreToolUse merge guard and
   `stop-after-completion` see it.
5. `gh pr view <n> --json state,mergeCommit,headRefOid`: `MERGED` at H gives the
   completion comment and a `state=merged` queue line; anything else gives
   `state=failed`, a record and a referral.
6. Before the next item: `git fetch origin`, then step 1 for it. Its manifest
   names the old B, so it is unresolved until update-branch, CI, a delta
   Review, a new orchestrator check, a new manifest and a new window.

## Revocation and recovery

A wake or resumed session runs `merge-risk-evidence.sh --queue` first and
reconciles every `executing` entry against the PR before anything else: merged
means record completion; still open means refer, never retry blindly; an unknown
outcome stops and refers. Queue lines are append-only, keyed (repository, pr, H,
decision_id); a key executes at most once.

The off label on the control issue, `enabled: false`, a closed control issue or
a configuration digest change turns every pending decision into a
maintainer-approval item; old records do not revive. The off label on one PR or
issue refers that item only. Only the maintainer re-enables, by a config PR
(reserved, so a human-path merge), then new records: an off label on the control
issue after the last config change is `off-since-config` (referred) even once
removed. An incident (an incorrect autonomous merge, an
ignored hold, suspected forgery) disables autonomy: add the off label to the
control issue, record the incident there, refer.

## Human-path interaction

Outside the class, with any disqualifier, dissent, missing evidence or revoked
autonomy, today's rule applies with every lapse rule of WORKFLOW.md step 4.
An explicit maintainer approval of an in-class PR is a human-path merge, recorded
as such; the panel record is linked but not required. Relays and wakes count
only his verbatim words about that exact PR and decision; a paraphrase, a
general go-ahead or an approval of another PR neither releases a hold nor
authorizes a merge. A 5-0 vote outside the class does not merge. A work item
into a release branch keeps the release workflow's own path and a release
branch into `main` keeps the maintainer's confirmation; both are referred here.
#646's own PR touches reserved paths and cannot merge under its delegation.

## Statistics

Live narrow start: no shadow phase, no 40-case sample and no first-ten
maintainer review. Enabling happens only by a change that links the maintainer's
recorded acceptance of #646. Coverage upper bound: 22 of 80 (27.5%) main merges,
cited from A55 on `feature/646-merge-risk-panel` 9621de6, not re-run; fully
evidenced eligibility is unknown. Per configuration revision and class list the
orchestrator posts on the control issue, from the records: candidates, each veto
reason, eligible 5-0, holds, referrals and dissent, merges, failures, reverts,
incidents, time to merge and actual token usage (`n/a` when unavailable).
Widening only through a reserved, maintainer-approved config PR; a success
streak never changes defaults. Token cost is not a gate; no payback claim.

## Residual risks

1. Records, labels, positions and the acceptance comment are forgeable on the
   shared login: the verifier proves equal bytes and an account, not honest
   authors.
2. The hold read and the merge are not atomic; a hold added in between is
   found afterwards, as an incident.
3. Three positions are conditional and written before the final diff.
4. The verifier binds only if it is run; skipping it is not mechanically
   blocked.
5. Semantic disqualifiers rest on Reviewer judgment.
6. The session-start slot that points here has little headroom.
7. The skill reaches adopted projects (inert) before #679 explains it.
8. A revert does not undo what adopters already pulled.
9. The check against B runs inside the code it checks: it catches drift, not
   a deliberately substituted verifier, and the guard the hook runs at the
   literal merge is not verified.
10. The reserved list is kept complete by a test of static references in the
    forms it knows; `gh`, `git`, `python3`, `bash` and GitHub are outside it.
11. `now` and T are GitHub's clock, to the second.
12. Any hold ever placed costs a maintainer quote, and a global off costs a
    config PR.
