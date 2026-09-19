# Adoptable changes

Every PR on this repo that adds something a project must make its own choice
about adds one entry here. Without an entry, the mechanism asks projects no
question, and you mistakenly think you're covered — see the `adoption-registry`
skill.

Per entry:

- **Question** — closed, answerable with yes/no. Keep it on one line:
  `pending-changes.sh` only shows that first line.
- **Default** — `yes` (generally desirable, unless a project has a reason to
  deviate) or `question` (no general preference, depends on the project).
  This is the **product default** per topic — a defensible starting value
  for every new adopter, not a derived category and not a prescription.
  Ties' own answers in the four existing projects (each `WORKFLOW-ADOPTION.md`)
  are a worked example of how that default was applied, not something a new
  adopter has to copy. Only determines the starting point: `adopt.sh` seeds
  `yes` entries at adoption with a provisional stamp; `question` entries never
  seed. **Neither means silent acceptance** — see the substantiation step in
  the `adoption-registry` skill: `yes` rows still need to be objectively
  substantiated when `PRD.md`/`ARCHITECTURE.md` are written (or changed to
  `no`), `question` rows get a reasoned proposal instead of a blank question.
- **Applies if** — one of the predicates from `lib/changes.sh`, the library
  both `adopt.sh` and `pending-changes.sh` source. That list lives there and
  not here: a third copy in prose would sooner or later drift out of step
  with the code. The condition is re-evaluated every session, so a change
  still surfaces once it becomes relevant for a project.
- **Yes means** — what concretely happens on a `yes`.
- **PR** — the linkback (W21, F15): the PR that establishes this. That's the
  PR that actually delivers the underlying capability, not necessarily the
  PR that last touched this row. On a later rewrite, rename, or split (like
  `technical-debt-en-refactoring`, which W6 split into
  `process-technical-debt-register` and `process-refactoring-triggers`), the
  linkback keeps pointing at the PR that built the thing itself, not at the
  restructuring of this file — otherwise half the entries would suddenly
  point at the same "make it finer-grained" PR, and that tells a project
  nothing about *why* the question exists. `./check` only verifies that the
  field is a URL, not that it points at the right PR — that stays human work
  when writing the entry.

The ID is the heading (`##`). Never change an existing ID **once a project
has answered it** — projects reference it in their own
`WORKFLOW-ADOPTION.md`, and a rename makes the question resurface there.
An entry nobody has answered anywhere yet may be revised or replaced;
check that with `grep` across every `WORKFLOW-ADOPTION.md` before doing so.

**Section separators** are `###`, entries are `##`. That distinction isn't
cosmetic: the parser reads every `## ` heading as an entry, so a subheading
at that level would become a nameless entry.

**Naming.** The `spec-` prefix is reserved for the fifteen NFRs — one per
subsection under *Non-functional characteristics* in `templates/PRD.md`, and
nothing else. The review scope in the `pre-merge-review` skill keys on that
prefix, so a non-NFR named `spec-` would get wrongly swept into it. Process
agreements get `proces-`, test levels get `test-`.

**Retiring an entry.** Take it out of this file. Never answered anywhere?
Then just delete it — check that with a `grep` across every
`WORKFLOW-ADOPTION.md` file. Answered somewhere? Then move it to
`CHANGES-ARCHIEF.md`, with the ID unchanged and an explicit reason, so a
project can trace where its row came from. See that file for the full
procedure.

Don't leave the entry inert by just dropping the fields: since section
separators are `###`, a `## ` heading here is unconditionally an entry, and
the shared parser warns if it has no `Applies if`.

---

## ci-convention

- **Question:** Must this project follow the CI convention (CI calls only `check`, no separate checks in the workflow YAML)?
- **Default:** yes
- **Applies if:** has-package-json
- **Yes means:** the project has a `check` script covering typecheck, lint,
  tests, and build, and a CI workflow that calls only that script.
  `adopt.sh` scaffolds `templates/ci.yml` if there's no workflow yet; a
  custom, more elaborate workflow is fine, as long as it follows the
  convention.
- **PR:** https://github.com/TiesL/claude-workflow/pull/2

## deploy-guards

- **Question:** Must this project apply the deploy-guards?
- **Default:** yes
- **Applies if:** has-deploy-script
- **Yes means:** the deploy script refuses to run from an unverified state,
  with the conditions per target environment from the `deploy-guards`
  skill. If that's not yet the case, make it a work item.
- **PR:** https://github.com/TiesL/claude-workflow/pull/3

## ci-on-pr-and-main

- **Question:** Must this project's CI run on pull requests *and* on pushes to `main`?
- **Default:** yes
- **Applies if:** has-package-json
- **Yes means:** the workflow has both a `pull_request` trigger and
  `push: branches: [main]`. The difference from only a push on the branch is
  substantial: `pull_request` evaluates the merged result, so it catches the
  case where two separately-green branches break together, and it's the
  form that can be set as a required check on a pull request. The push
  trigger is the backstop for whatever reaches `main` some other way. This
  is separate from `ci-convention`: that answer is about *what* the workflow
  does (call only `check`), this one is about *when* it runs. A project
  that already answered the first is never asked about the second.

  Two things worth knowing before answering "yes". First, this drops
  validation for a push to a feature branch with no pull request yet: the
  first CI signal then only arrives once the PR opens. That's the price of
  evaluating the merged result, and small in a workflow where the PR opens
  early. Second, this question inherits the scope of `has-package-json`:
  a project with a CI workflow but no `package.json` doesn't get it, same
  as `ci-convention`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/50

## ci-link-3-hard-block

- **Question:** Does this project's CI fail a pull request that references no issue (link 3, hard block)?
- **Default:** yes
- **Applies if:** has-package-json
- **Yes means:** `check-pr-issue-link.sh` is scaffolded (`adopt.sh`, see
  `templates/check-pr-issue-link.sh`) and the workflow calls it on the
  `pull_request` event, with the PR number as argument — see
  `templates/ci.yml`. Only the triggering PR is judged, no audit over
  history (F13 decision d, W19b). This is separate from `ci-on-pr-and-main`:
  that answer is about *when* the workflow runs, this one about an extra
  step it also performs. `scaffold_if_missing` never overwrites an existing
  `ci.yml`, so a project that already had one before W19b doesn't get the
  step automatically — this question makes that visible instead of letting
  it lie dormant. Since issue #85, `templates/ci.yml` also carries the
  `permissions: pull-requests: read` block this step needs — without it,
  it blocks every PR. Since issue #106, that block also includes
  `issues: read`: `closingIssuesReferences` (which this step reads) is
  about the linked issue itself, not the PR, and silently returns an empty
  list without that scope, even when the link genuinely exists —
  `pull-requests: read` alone turned out not to be enough (demonstrated
  empirically on PR #105, the same gap but in this repo's own workflow,
  issue #99). A project that scaffolded before #106 is missing
  `issues: read` — check that both `pull-requests: read` and `issues: read`
  apply to the `check` job (job- or workflow-level) — and must otherwise
  add it by hand or re-scaffold.
- **PR:** https://github.com/TiesL/claude-workflow/pull/75

## ci-detects-main-outside-pr

- **Question:** Does this project's CI fail a push to `main` that doesn't come from a pull request?
- **Default:** yes
- **Applies if:** has-package-json
- **Yes means:** `check-main-via-pr.sh` is scaffolded (`adopt.sh`, see
  `templates/check-main-via-pr.sh`) and the workflow calls it on the
  `push` event to `main`, with the commit SHA as argument — see
  `templates/ci.yml`. Detection, not prevention: the command has already
  run by then, but it's the only mechanism that works without GitHub
  Pro/a public repo (W27, F17). Judges only the incoming push, no audit
  over history. If the origin can't be established, the check fails —
  deliberately the opposite of the native git hooks (W26, `adopt.sh`
  always installs those, with no adoption question of their own), which
  let a push through when in doubt. `scaffold_if_missing` never overwrites
  an existing `ci.yml`, so a project that already had one before W27
  doesn't get the step automatically — this question makes that visible.
  Since issue #85, `templates/ci.yml` also carries the
  `permissions: pull-requests: read` block `check-main-via-pr.sh` needs —
  its absence is exactly what issue #83 exposed: that check called
  `gh api .../commits/$sha/pulls` and failed under the default, minimal
  token scope (which already includes `contents: read`). A project that
  scaffolded before that fix is missing the block — check whether
  `pull-requests: read` applies anywhere to the `check` job (job- or
  workflow-level) — and must otherwise add it by hand or re-scaffold.
- **PR:** https://github.com/TiesL/claude-workflow/pull/76

## traceability-link-1

- **Question:** Must this project offline-check that every functionality in `PRD.md` is covered by at least one scenario in `TEST-SCENARIOS.md`?
- **Default:** yes
- **Applies if:** always
- **Yes means:** the project has `check-traceability.sh` (scaffolded by
  `adopt.sh`) and calls it from its own `check`. Scenarios carry a
  `**Covers:**` field pointing at the functionality they describe.

  **"Yes" means retroactively too.** That's a deliberate choice, not a side
  effect. The script enforces at file level: as long as *no* scenario
  carries a `Covers:` field, it only warns — but once the first field is
  there, the requirement applies to **all** functionality in the PRD, even
  items unrelated to that piece of work. There's no gradual ramp-up: whoever
  fills in the field for the first time without bringing the rest along
  turns the project's entire backlog red in one commit.

  So only answer "yes" once the existing scenarios have their `Covers:`
  fields. For a project with a real backlog, that's its own piece of work,
  not a side note on the next PR — budget one line per scenario plus the
  judgment call of which scenario actually covers which functionality.

  Two more things that apply. A `PRD.md` with no ID headings is a warning,
  not an error: link 1 can't be checked there. And **duplicate IDs are a
  hard error**, even with no `Covers:` field at all — a reference to an ID
  that occurs twice can't be resolved unambiguously. A project with
  duplicate IDs fixes those first; `tennis-invoicing` is that case today.

  The prefix isn't fixed: `F`/`S` is customary, but a project that numbers
  its scenarios `R`/`A`/`B`/`P` works unchanged. Only the field counts — an
  ID in running text is not a reference.
- **PR:** https://github.com/TiesL/claude-workflow/pull/63

---

### Process and design depth

## process-prd

- **Question:** Does this project maintain a `PRD.md` as its normative specification?
- **Default:** yes
- **Applies if:** always
- **Yes means:** `PRD.md` exists and is kept current (as-built or design) — see `templates/PRD.md`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## architecture-document

- **Question:** Must this project record its architecture decisions in `ARCHITECTURE.md`?
- **Default:** yes
- **Applies if:** always
- **Yes means:** structural choices (platform, layers, data ownership, substantial dependencies) are recorded with criteria, weighed options, the decision, the architecture requirements that follow from it, and when the choice should be revisited. `adopt.sh` scaffolds the template.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## process-context-document

- **Question:** Does this project maintain a `CONTEXT.md`: project jargon → meaning?
- **Default:** question
- **Applies if:** always
- **Yes means:** `CONTEXT.md` exists and is kept living — updated as a new
  term arises or changes meaning, not attempted complete in one go.
  Separate from `ARCHITECTURE.md`, which is about structural decisions, not
  language. `adopt.sh` scaffolds the template once this row is `yes`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/72

## process-issue-tracking

- **Question:** Does this project split work into GitHub issues (epics/work items)?
- **Default:** question
- **Applies if:** always
- **Yes means:** `adopt.sh` refreshes `.github/ISSUE_TEMPLATE/`, and work gets split from the PRD into an `Epic` issue with `Work item` issues — see `templates/ISSUE_TEMPLATE/`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## test-unit

- **Question:** Does this project have unit tests for its core logic?
- **Default:** yes
- **Applies if:** always
- **Yes means:** the core logic (ideally a domain layer with no external dependencies — see `spec-testability`) has unit tests, and `check` runs them.
- **PR:** https://github.com/TiesL/claude-workflow/pull/6

## test-feature-gwt

- **Question:** Does this project describe functionality as Given/When/Then scenarios?
- **Default:** yes
- **Applies if:** always
- **Yes means:** `TEST-SCENARIOS.md` exists and covers every functionality item from the PRD with at least one Given/When/Then scenario for the expected behavior — see `templates/TEST-SCENARIOS.md`. The failure scenarios alongside those fall under `spec-failure-modes`.
- **PR:** https://github.com/TiesL/claude-workflow/pull/1

## test-tdd-seams

- **Question:** Does this project work test-first on pre-agreed seams, with red-before-green discipline?
- **Default:** yes
- **Applies if:** always
- **Yes means:** tests touch only the public boundary (never internal
  implementation details), are demonstrably red before the implementation,
  and avoid the three named anti-patterns (implementation-coupled,
  tautological, horizontal slicing) — see the `tdd-seams` skill. On top of
  `test-unit`/`test-feature-gwt`, which only ask *whether* there are tests,
  not how.
- **PR:** https://github.com/TiesL/claude-workflow/pull/72

## test-integration

- **Question:** Does this project have automated integration tests (across component boundaries, against a real or simulated external dependency)?
- **Default:** question
- **Applies if:** always
- **Yes means:** besides unit tests, there are tests verifying the collaboration between components (or with an external platform), and `check` runs them — or an explicit reason why that isn't proportionate for this project.
- **PR:** https://github.com/TiesL/claude-workflow/pull/6

## quality-review-before-merge

- **Question:** Must every PR in this project get a quality review before the merge, with findings in the PR?
- **Default:** yes
- **Applies if:** always
- **Yes means:** before the merge, a review runs with fresh context and on
  a different model than the one that wrote the code — same model only
  when no other capable model is genuinely available, and then recorded
  as an explicit exception (`same-model-exception`), never silently
  treated as satisfying this (#244; resolves a prior contradiction with
  `pre-merge-review`'s own wording, which used to say only "at least as
  skilled," permitting same-model review by omission). The review always
  checks complexity and dependencies (basic hygiene), plus exactly the
  NFRs whose corresponding `spec-*` question this project answered "yes"
  to. Findings go into the PR; every finding is either resolved or
  recorded under *Technical debt* in the PRD.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## ci-gate-on-merge

- **Question:** Does the merge guard also block `gh pr merge` when the PR has checks that didn't pass (alongside the existing block on a missing review marker)?
- **Default:** yes
- **Applies if:** always
- **Yes means:** the same guard that already blocks on a missing
  `pre-merge-review` marker (see `quality-review-before-merge`) now also
  blocks when `gh pr checks` reports a check that isn't `pass`/`skipping` —
  found after CI turned out red for six runs in a row, unnoticed (issue
  #81). Fails open without `gh`, network, or reported checks: a project
  with no CI (`ci-convention` doesn't apply, or isn't answered yet) reports
  no checks and so isn't blocked. The same `no` on
  `quality-review-before-merge` disables both checks — this isn't an
  independent on/off switch, since it's the same gate.
- **PR:** https://github.com/TiesL/claude-workflow/pull/82

## stray-closes-guard

- **Question:** Does the merge guard also block `gh pr merge` when a commit on the PR carries a closing keyword (`Closes #N`, `Fixes #N`, ...) for an issue the PR's own title/body doesn't also close?
- **Default:** yes
- **Applies if:** always
- **Yes means:** the same guard blocks when any constituent commit's
  message references an issue via GitHub's own closing-keyword grammar
  that isn't also in the PR's `closingIssuesReferences` — found concretely
  when an intermediate commit's "Closes #218" (a note-to-self, unrelated
  to that PR) survived into the squash-merge commit's message (which
  concatenates every constituent commit by default) and closed that issue
  for real (issue #223). Fails open without `gh` or network. The same
  `no` on `quality-review-before-merge` disables this check too — same
  gate, same rule as `ci-gate-on-merge` above.
- **PR:** https://github.com/TiesL/spec-driven-guardrails/pull/224

## process-technical-debt-register

- **Question:** Does this project keep a separate Technical debt register alongside Known limitations?
- **Default:** yes
- **Applies if:** always
- **Yes means:** `PRD.md` separates *Known limitations* (stays that way) from *Technical debt* (per line: why acceptable for now, and the trigger to address it) — both subsections are already in the template.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## process-refactoring-triggers

- **Question:** Do the refactoring triggers from the `refactoring-triggers` skill apply to this project?
- **Default:** yes
- **Applies if:** always
- **Yes means:** a work item that would violate the recorded design doesn't get built anyway through a workaround — that's the signal for its own redesign work item. See the `refactoring-triggers` skill. The first trigger presupposes a recorded design; if this project has no `ARCHITECTURE.md` (see `architecture-document`), only the second and third trigger apply.
- **PR:** https://github.com/TiesL/claude-workflow/pull/5

## process-diagnose-bug

- **Question:** Does this project follow the mandatory order reproduction → hypotheses → regression test → fix when diagnosing a bug?
- **Default:** yes
- **Applies if:** always
- **Yes means:** first a deterministic, self-runnable reproduction; then
  falsifiable hypotheses, shown before they're tested; then a regression
  test that's red on the reproduction; only then the fix — see the
  `diagnose-bug` skill. A fix with no prior failing test proves nothing.
- **PR:** https://github.com/TiesL/claude-workflow/pull/72

## process-model-choice

- **Question:** Does this project apply capability/cost-aware model
  selection at every artifact-producing pipeline stage (Discovery,
  Planning, Test authoring, Implementation, Review) — not only at review?
- **Default:** yes
- **Applies if:** always
- **Yes means:** each stage's floor is assessed on that stage's own
  demands, never inherited from a previous stage's model, and stated
  qualitatively — never a model name or tier — so the rule doesn't go
  stale as new models ship. Above that floor, the cheapest model/effort
  combination that clears it. Every stage after Discovery anchors its
  floor to whichever model handled the stage before it (Review already
  worked this way); Discovery, having no predecessor, floors directly on
  the task's own demands. Every stage records which model/effort was
  used, always — see the `model-choice` skill.
- **PR:** https://github.com/TiesL/spec-driven-guardrails/pull/236

---

### Non-functional characteristics (NFRs)

The fifteen non-functional characteristics don't live here but in `nfr/` —
one file per characteristic, with the question, what "yes" means, and the
guidance together. They used to live both here and in `templates/PRD.md`
and had to be kept in sync by hand; now both are consumers of that same
register.

The scripts read both `CHANGES.md` and `nfr/`, so nothing changes for a
project: the same questions, at the same moments. Retirement there goes via
the `status: retired` field instead of a move to the archive.
