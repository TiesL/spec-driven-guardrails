---
name: write-spec
description: >
  How work gets specified: keeping PRD.md and TEST-SCENARIOS.md up to
  date, splitting work into GitHub issues, and the Covers:-convention
  (token grammar, traceability) that links scenarios to functionality.
  Use this when drafting issues, PRD sections, or test scenarios.
---

## Specifying work (PRD, test scenarios, issues)

1. Every project keeps a `PRD.md` (as-built or design) and
   `TEST-SCENARIOS.md` (Given/When/Then) — see `templates/` in this repo
   for the format. When a new project is adopted, `adopt.sh` scaffolds
   both automatically if they don't exist yet.
2. Work is split from the PRD into GitHub issues: one `Epic` issue for the
   whole, `Work item` issues per part to be built (see
   `templates/ISSUE_TEMPLATE/`). Create the issue before development.
   Work on `wip/<issue-number>-<short-desc>`; reserve `feature/...` and
   `fix/...` for validated PR publication. See `WORKFLOW.md`, "Branch strategy".
3. Every work-item issue has its own Given/When/Then acceptance criteria
   and refers to the matching scenarios in `TEST-SCENARIOS.md` — so every
   issue is directly usable to test the built software against.
4. Implementation divergence requires owning-role reconciliation, never
   rewriting the oracle to fit code. Spec/scenario conflicts follow OR19
   and the stop/preservation rule in `role-contracts`.

Each current/existing/unchanged-behavior clause needs a falsifying command or
check, observable expected result and Product/QA run evidence or concrete evidence
lookup. Record the observed main SHA and the PR's main merge-base SHA separately
when different. Preservation assertions run on that merge base. Unverified claims
remain unresolved; revalidate relevant main changes before merge. A contradicted
historical claim is a spec finding, not an accepted oracle.

For the substantiation requirement when drafting or revising
`PRD.md`/`ARCHITECTURE.md` — see the `adoption-registry` skill.

Does this project have a `CONTEXT.md` (project jargon → meaning, separate
from the structural decisions in `ARCHITECTURE.md`)? Update it as soon as a
new term arises or an existing one changes meaning — don't try to make it
complete in one pass.

## Maintaining issue and board metadata

At creation, relationship or stage changes, reprioritization and closure,
maintain the settled issue record and its mirrors. Issue-body fields are the
portable authority for relations. Native parent/blocker relations mirror settled
body declarations; board Backlog rank and Horizon are authoritative for order.
The owner prepares body changes and decisions first. In role pipelines Product
owns authored body reconciliation, including inverse edges; the orchestrator
publishes owner-produced content unchanged and mirrors already-decided metadata
under OR46. Unsettled content/order returns to Product and the maintainer.
Mirroring grants no prioritization, repair or project-configuration authority.

Read current data before applying settled changes, then read back and verify.
This sequence is non-atomic: record completed, failed and unchecked operations,
with affected issue/edge and desired state, in the Pipeline log (or a durable
issue note outside role pipelines). Never call a partial sequence synchronized.
After failure re-read and reconcile; never guess a repair or rollback state.
Missing/duplicate/malformed body fields or failed reads mean unchecked scope,
not an empty set and not permission to delete a relation.

**Bodies and labels.** Each work item has one live whole-line `**Epic:** #N`,
realized `**Covers:**` tokens, and explicit `**Blocked by:**` / `**Blocks:**`
sets; write `none` for each empty dependency set. Top-level epics have no parent
and list children under Work items; nested epics also name their Epic. Epic
bodies carry Covers and dependencies too. Ignore quoted, fenced, inline-code
and indented-code examples using `lib/markdown.sh`'s live-text convention.
Keep parent child lists reciprocal with child Epic and keep both dependency
ends consistent: A Blocked by B iff B Blocks A. Read every affected end,
including old parents and removed blockers. Remove obsolete edges and old
parent entries from both bodies and native mirrors when their removal is
settled. Contradictory bodies need owner reconciliation before mirroring.

Maintain type/status and the active-role label using the existing vocabulary
and canonical stage order. Inactive/backlog/closed items need no invented active
role. Closed items drop active status/role labels. For this repository's Project
1, mirror backlog to Backlog, Discovery through Implementation to In progress,
Review to In review, verified closure to Done; Ready requires an explicit ready
decision. Blocked work retains its applicable stage Status and visible blocker
reason/label: there is no Blocked option. Other projects use their documented
mapping; missing mapping/options are unchecked, never authority to configure.

**Membership and ordering.** Confirm automatic membership before attempting an
add; allow existing auto-add workflows to act, add only confirmed missing items
and verify fresh membership. A duplicate/already-exists response requires a
re-read. Parent/progress/linked-PR fields are derived; do not edit them directly.
Apply only confirmed order and Horizon values from the maintainer. Child rank
follows inheritance from its epic unless the epic gives an order (#721); lower
Backlog rank is earlier. Pick the lowest-ranked unblocked item; unranked items
are unordered. Change order in board fields. Proposals remain unapplied until
confirmed; do not infer priority from issue number or rank children independently.

Each empty field needs a durable reason and decision reference in the issue
body's Board decisions table (or an equivalent durable issue comment). Use one
row per Backlog rank / Horizon, with these columns:

| Field | Reason | Proposed value | Disposition | Decision/reference |
| --- | --- | --- | --- | --- |
| Backlog rank | Inherits epic order; confirmation pending | undecided | awaiting-maintainer | Parent issue/decision URL |

The disposition is `awaiting-maintainer` or `parked`; awaiting notes explicitly
retain the pending proposal (or `undecided`), and parked fields cite the
documented parking decision. Maintainer-decision items, parked epics and new
issues can remain unranked under #721, but each empty field still needs this
record. One documented field cannot excuse the other missing Horizon/rank.
Read all comments too. Generic priority TBD or an unlinked label is insufficient.
A confirmed board value supersedes its old awaiting note; contradictory unresolved
notes are indeterminate. An exception records an empty field, never authorizes
applying the proposal.

**Read/apply/read-back recipe.** Use explicit `R=OWNER/REPO` and validated issue
numbers/IDs, never eval or token values. Read `gh api repos/$R/issues/$n`,
`.../parent`, `.../sub_issues`, `.../dependencies/blocked_by` and
`.../dependencies/blocking`; paginate all lists and comments. Use REST numeric
IDs, distinct from issue numbers, node IDs and project-item IDs.

- Add a settled parent with `gh api --method POST repos/$R/issues/$parent/sub_issues
  -F sub_issue_id="$child_id"`; remove the old one with `--method DELETE
  repos/$R/issues/$old_parent/sub_issue -F sub_issue_id="$child_id"`. Never blindly
  replace a parent on incomplete evidence. Verify both parent and child reads.
- Add a blocker with `gh api --method POST
  repos/$R/issues/$blocked/dependencies/blocked_by -F issue_id="$blocker_id"`;
  remove with `--method DELETE
  repos/$R/issues/$blocked/dependencies/blocked_by/$blocker_id`. Verify the
  corresponding blocking read on the blocker too.
- Publish existing labels with `gh issue edit "$n" -R "$R" --add-label ...
  --remove-label ...`. Publish owner-produced body text through `--body-file`,
  preserving newlines and content; never interpolate bodies into shell code.
- Resolve the configured project's complete item inventory, field IDs/types and
  option IDs first. Only after confirmed absence, use `gh project item-add
  "$project" --owner "$owner" --url "$issue_url"`. For decided fields use
  `gh project item-edit --id "$item_id" --project-id "$project_id" --field-id
  "$field_id" --number "$rank"`, or `--single-select-option-id "$option_id"`
  for Horizon/Status. Use `--clear` only for an explicitly decided removal.
  Verify every value with fresh reads; do not change workflows or create fields.

Check command shapes against installed gh help/endpoint contracts before live
maintenance. Supported explicit no-parent responses differ from ambiguous 404s:
unsupported/unavailable endpoints are unchecked. Record operation/issues and
unchecked scope for permissions, rate limits, malformed JSON, GraphQL errors or
partial pagination. Do not expose raw headers, credentials or server stderr,
change scopes or retry writes blindly. Fake-gh tests prove request behavior,
not live server success; record authorized add/remove/read-back evidence before
claiming live maintenance.

**On-request report.** `backlog-drift.sh` is a read-only report with no write mode:
`./backlog-drift.sh --repo OWNER/REPO --project-owner OWNER --project N`.
Adopters can invoke `$SPEC_DRIVEN_GUARDRAILS_DIR/backlog-drift.sh`; omitted repo
uses gh's current-repository placeholders. Board arguments are a pair from the
project's documented configuration; do not discover an arbitrary board. The
report reads open and closed issues, native relations, all comments and complete
project connections, including field-value pages and archived items where exposed.
Report observed and expected values with evidence URLs, valid exceptions and
unchecked scope. `result=clean` requires complete applicable reads and no drift;
`incomplete` retains known findings. Missing gh/network is advisory incomplete.
It exits 0 for advisory results, 2 for invalid usage and 1 for internal errors.
It is no CI/merge gate, session-start hook or automatic repair.

Without a board retain portable bodies, labels and applicable native mirrors;
board checks are not-applicable (membership, rank, Horizon and Status). Native
relations do not require Projects. An inaccessible configured board is incomplete,
never absent. Without native access preserve portable records and record pending
external operations; do not claim maintenance happened.

**Verified closure.** Use existing workflows first before manual corrections,
then verify CLOSED and board Done through fresh reads, including membership.
Record child completion and the PR link, verify the real issue/PR linkage and
required `Closes #N` in the PR description rather than assuming text populated a
derived field. A release merge does not establish closure: under
`release-branch-workflow`, confirm the child PR merged to release, record its
completion, explicitly `gh issue close "$n" -R "$R"`, then verify CLOSED and
Done. Keep the epic open under its existing release rules. Correct a remaining
Status only to settled Done and verify it. Do not add duplicate automation or
change epic-auto-close/workflow settings because automation was assumed absent.

## Recording coverage with `Covers:`

Every test scenario carries a `**Covers:**` field under its heading, with
the functionality from `PRD.md` it describes. Comma-separated when there's
more than one. The token form is a fixed grammar: `^[A-Z]{1,2}[0-9]+[a-z]?$`
— for example `F1`, `S2`, or `S2b`. Two leading letters is also allowed
(`OP4`), and that trailing letter (`S2b`) is existing usage, not sloppiness.

Two rules you shouldn't work around. **The prefix isn't fixed**: `F`/`S` is
customary, but a project that numbers its scenarios `R`/`A`/`B`/`P` works
unchanged — the check verifies that a token resolves to an existing
heading, not which letter comes before it. And **only the field counts**:
an ID that appears in running text isn't a reference, otherwise any
sentence that happens to mention "S1" would produce coverage that isn't
really there.

`check-traceability.sh` checks this offline, invoked from the project's
`check`. It isn't retroactive: as long as no scenario carries the field, it
only warns. But note what that means — once the first field appears, the
requirement applies to **all** functionality in the PRD, even items
unrelated to that piece of work. If you fill in the field for the first
time in a project with an existing backlog, do so in a PR that also
addresses that backlog or deliberately records it as debt.
