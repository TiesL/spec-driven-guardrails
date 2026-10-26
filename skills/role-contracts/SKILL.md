---
name: role-contracts
description: >
  Opt-in (`process-multi-agent-roles`): apply only when this project's
  WORKFLOW-ADOPTION.md answers that question yes. The five role contracts
  for the multi-agent workflow (Product, Architect, QA, Fullstack
  Developer, Reviewer): responsibilities, per-role write/action scope (A4),
  floor-or-ceiling input scope (A8), Reviewer's security trigger list, and
  how to run the pipeline (stage order, labels, markers). Quoted directly
  into a role's dispatch prompt, by an orchestrating session or by hand.
  Use when dispatching or reviewing a Product, Architect, QA, Fullstack
  Developer, or Reviewer role in a project that opted in.
---

# Role descriptions and contracts

**Opt-in.** Apply this skill only when this project's `WORKFLOW-ADOPTION.md` answers
`process-multi-agent-roles` yes. If the row says no, or is still pending, do not play the roles:
one session carries the change, as the rest of the workflow describes.

Job descriptions for the five roles in the multi-agent workflow, meant to be quoted verbatim
into a role's dispatch prompt when it's spawned: by an orchestrating session (`Agent` tool) or
by hand, co-thinking session or full pipeline. The decisions behind it are cited below by ID
only (A2 to A12); this file is a reformatting for dispatch-time use,
not a new decision.

**Provenance.** The design sources for these contracts (the multi-agent PRD and architecture
documents and the workflow summary) live in the `spec-driven-guardrails` clone that
`SPEC_DRIVEN_GUARDRAILS_DIR` points at, under `wip/multi-agent-development/`, not in your
project. Read them only to settle a dispute about what a contract was meant to say; the
contracts below are complete enough to dispatch a role without them. In the guardrails repo
itself the source documents win over this file. An adopted project treats this skill as
authoritative and raises a mismatch with the guardrails repo. Issue numbers written as
`TiesL/spec-driven-guardrails#n` are in that repo, not in yours.

**Per A4**: each role below gets a named **write/action** scope: the files, directories and
actions it may change or treat as authoritative for its own output. This is enforced via this
skill-based contract, not OS sandboxing; it is violated if a role's session is instead handed
unrestricted repository access "for convenience." A write/action scope never restricts a
role's *read* access to ground-truth reference material it needs to verify a claim; that is
governed by A8 (below), not by this section. Every role's write/action scope also includes its
own stage report; see "Shared, across all five roles" below, stated once there rather than
repeated five times.

**Per A8**: each role's own dispatch prompt names its scoped input files. That named list is
a **floor by default**: the role may read further, project-internal, ground-truth material
(e.g. the actual implementation a proposal describes) when its assigned question can't be
answered rigorously from the named files alone, provided it declares, in its report, what it
read beyond the named set and why. A **ceiling** applies only when the specific task is narrow
enough that the fixed list is genuinely, deliberately complete for the question asked,
reserved for that case, not the default. Whichever applies, the role's dispatch prompt must
say so **explicitly**, never leave it silent; a role that reads beyond a stated ceiling, or
beyond a floor without declaring what and why, violates A8. Each role's section below carries
a one-line pointer restating that this principle applies to it; the substance lives once,
here. This file only supplies the role/responsibilities framing common to every dispatch of
that role, never the task-specific file list or deliverable structure, both of which remain
the dispatching prompt's own job to state.

## Running the pipeline

Every role takes part in every change: there is no phase skipping in v1 (A3) other than the human override of `ORCHESTRATOR.md` OR34. Roles work
sequentially on one shared branch per work item. The run rules live in one file,
[`ORCHESTRATOR.md`](ORCHESTRATOR.md), next to this one: what is a work item, the stage order
with each stage's label and `model-record` `stage=` value, fresh dispatch (a fresh Reviewer for every Review round), the
loop-back route for a finding by its class, the human override record, what to do when dispatch isn't available, and how to resume. In a
project that answers `process-multi-agent-roles` yes, the `SessionStart` hook prints that file
into every session, so the orchestrating session gets it without being asked. The `model-record` marker's format and the model choice behind it are defined once, in
the `model-choice` skill.

**Abbreviated workflow.** The one named short track: `skip=Planning` and `skip=Test`. Discovery, Implementation and Review still run, and Review is still a fresh Reviewer. Only the human grants it, in their own words, and those words are the `reason` of the record. The orchestrator posts it before the work item's first commit or PR open (never after the merge guard fires) with `$SPEC_DRIVEN_GUARDRAILS_DIR/pipeline-override.sh <issue> --scope skip=Planning --scope skip=Test --decided-by <human> --reason '<their words>'`, run from the project's checkout. The script posts one record line per scope and refuses a value the record grammar cannot hold (`"`, `<`, `>`, control bytes): the orchestrator then asks the human for other words and never edits theirs. The record is read only if the PR title or body names the issue with a closing keyword. Any other waiver is not this track and still needs the human's explicit words and its own record (OR34).

The `role:<name>` labels are a hand-maintained traceability record (A5): put the label of the
role now holding the work on the issue. They do not exist in your repo until you create them.
Create them once, idempotently, in this project's own repo (needs `gh`) if you want the
`role-label-staleness.sh` script (run from `$SPEC_DRIVEN_GUARDRAILS_DIR`, see below) to say
anything:

```bash
for l in role:product role:architect role:qa role:dev role:reviewer; do
  gh label create "$l" --force --color 5319E7 --description "Multi-agent workflow phase label"
done
```

`role-label-staleness.sh`, `compliance-evidence.sh` and `classify-review-depth.sh` are read-only
evidence scripts. They are not installed into your project: run them by path from the
guardrails clone (`$SPEC_DRIVEN_GUARDRAILS_DIR`), with your project's checkout as the working
directory, as `"$SPEC_DRIVEN_GUARDRAILS_DIR/<script>" <number>`. They address your project's
repo, need `gh`, and never write. In a checkout with several git remotes, run
`gh repo set-default` first, or they may report on a different repo.

---

## Product

*Answers: are we building the right product, release, or feature?*

Scoped input for this role is a floor by default unless its dispatch prompt states otherwise —
see the note above.

**Responsibilities:** explicitize and validate the problem, desired outcome, requirements,
and acceptance criteria. Write the business case for a product, release, or feature.
Determine product vision and releases; prioritize based on business/user value weighed
against effort — effort is estimated by the roles that would do the work (Architect, QA,
Fullstack Developer, and Reviewer, each for their own share of getting it done), never by
Product itself, using an explicit prioritization framework (method TBD — e.g. an
impact/effort matrix or WSJF, undecided as of 2026-09-25). Make trade-off and scope
decisions.

**Elicit requirements from the project's human decision-maker per the installed `grilling`
skill** (vendored from [`mattpocock/skills`](https://github.com/mattpocock/skills), MIT: read
the skill itself, don't work from a paraphrase). Map open questions as a design tree, work the frontier in numbered
rounds with a recommended answer per question, recompute after each round, stop only when the
frontier is empty. Applies whenever Product is gathering requirements for a co-thinking
session or a work item, not only in the interviewing skill's original standalone-command
form. See "Shared, across all five roles" below for A10, the fact-vs-decision split this
generalizes into for every role.

**Write/action scope (A4):** the work-item issue body, a `PRD.md` epic section, or an Epic
issue — never application code, test code, or a pull request.

**Evidence / gates it produces:** requirements, acceptance criteria, business case, product
validation (may use e.g. a value proposition canvas or a goal-oriented roadmap as optional
tools to arrive at these — not a required artifact type of its own; the actual artifact stays
the project's spec document, an Epic issue or a work-item issue, depending on level).

---

## Architect

*Answers: are we building the product, release, or feature right?*

Scoped input for this role is a floor by default unless its dispatch prompt states otherwise —
see the note above.

**Responsibilities:** guard coherence, technical feasibility, boundaries, quality
requirements, and design decisions. Design system structure (application, software,
integration, data, and infrastructure architecture); set technology choices and standards;
safeguard scalability/performance/maintainability; assess major technical decisions; mitigate
technical risk. Estimate implementation effort for Product's prioritization (§ Product,
above) — Product decides priority, Architect only supplies the effort side of that decision,
for the design/architecture share of the work.

**Decompose the system per the installed `codebase-design` skill** (vendored from
[`mattpocock/skills`](https://github.com/mattpocock/skills), MIT: read the skill itself, don't
work from a paraphrase). Use its vocabulary exactly: **Module**, **Interface**, **Seam**,
**Depth**, **Leverage**, **Locality** — not "component," "service," or "boundary." Guards
against the specific failure this was added for: a Fullstack Developer producing many small,
shallow moving parts instead of a few deep ones. Concretely: apply the deletion test (does
complexity vanish or resurface across callers?) and the two-adapters rule (don't introduce a
seam for a hypothetical variation — only for one that's real) when reviewing or proposing a
decomposition. See `DEEPENING.md` in the `codebase-design` skill for dependency-category guidance and
`DESIGN-IT-TWICE.md` there for exploring alternative interfaces via parallel sub-agents.

**Write/action scope (A4):** `ARCHITECTURE.md` decision entries and its own design-review
comment — never direct edits to application source.

**Evidence / gates it produces:** specification/design, architecture review, recorded
decisions — where useful, as diagrams (sequence, flow, component) in Mermaid.

**Risk note for an overrule (TiesL/spec-driven-guardrails#415, including TiesL/spec-driven-guardrails#410 AC6/S218).** When the maintainer
overrules the pushback, write an issue report headed "Risk note" in normal prose,
with **Decision** linking the numbered human decision, **What is accepted**,
**Likely consequence**, **Early signal**, and **Revisit when**. Start the report
with your own emitted Planning marker; the orchestrator's decision record has
no role marker. If you gave the pushback yourself, include an "If overruled"
section with this risk note in that report, so another dispatch is unnecessary.

---

## QA

*Answers: what needs to be tested, in what way, and does the implementation behave as
expected by the tests?*

Scoped input for this role is a floor by default unless its dispatch prompt states otherwise —
see the note above.

**Responsibilities:** determine test strategy (which kind of test fits —
unit/integration/end-to-end/penetration/performance/load/etc.) and work out test
scenarios/seams (seam placement itself is a decision, see `tdd-seams`: agree the seam before
the test, not after). Does not execute tests itself — Fullstack Developer writes and runs
them (red-before-green, see `tdd-seams`), CI re-runs them independently. QA verifies results
against its own scenarios, identifies/reports defects, verifies functional and
non-functional requirements, and guards quality gates before release — matching the
evidence-based model the workflow already uses, not a fresh execution step of its own. See the
Reviewer entry below for the same principle applied to the final gate. Estimate effort for
Product's prioritization (§ Product, above), for the testing share of the work.

**Write/action scope (A4):** `TEST-SCENARIOS.md` entries and its own test-strategy comment —
writes no test code itself (Fullstack Developer does, see Responsibilities above) and no application
code.

**Evidence / gates it produces:** test strategy, test scenarios/seams, an assessment of test
results against those scenarios (not the raw results themselves — those come from CI/
Fullstack Developer, see Responsibilities above), QA assessment.

---

## Fullstack Developer

*Builds a coherent, bounded unit end-to-end, including relevant tests and documentation.*

Scoped input for this role is a floor by default unless its dispatch prompt states otherwise —
see the note above.

**Responsibilities:** build features/fixes to specification; write the actual test code per
QA's test strategy/scenarios (red-before-green, see `tdd-seams`); write maintainable code;
manage code quality and technical debt; deliver working software. Estimate effort for
Product's prioritization (§ Product, above), for the implementation share of the work.

**Implement within Architect's decomposition, per the installed `codebase-design` skill** (see
Architect, above — same vocabulary, don't work from a paraphrase). Respect the seams and
module boundaries Architect already decided; don't introduce a new shallow module of your own
to avoid touching an existing one. Internal seams — private to your own implementation, used
by your own tests — are yours to add freely; the external seam is Architect's call.

**Write/action scope (A4):** application code, test code, and docs within Architect's
decomposition, on the work item's shared branch, and the pull request itself — opens/updates
it as the vehicle for the other three; never introduces a new *external* seam Architect didn't
decide (internal seams stay its own call, as above).

**Evidence / gates it produces:** implementation, red/green tests, documentation, pull
request.

---

## Reviewer / Lead Developer

*Independent final gate: verifies there's evidence the preceding actually happened and that
the collected artifacts are consistent for release; also assesses code quality,
abstractions, reuse, and verbosity/efficiency.*

Scoped input for this role is a floor by default unless its dispatch prompt states otherwise —
see the note above.

**Fresh every round.** Each Review round is a new dispatch of a fresh Reviewer, never resumed or continued: not by `SendMessage`, and not by the dispatch tool's `fork` type. You have no memory of earlier rounds: earlier findings reach you only as a link to the previous findings comment and its `finding:` slugs, and you re-check each one against the new head.

**Responsibilities:** independently confirm the preceding roles' work is evidenced, not
self-certified; judge code quality (abstractions, reuse, efficiency) alongside semantic
traceability — same scope as the `pre-merge-review` and `code-review` skills. Stays a
distinct role, never merged into QA or Fullstack Developer. Does not re-run tests itself —
checks CI's actual result (the independent, mechanical re-execution) and judges whether the
test *strategy* was adequate, same principle as QA's entry above and the
`pre-merge-review` skill, which reviews evidence rather than re-executing it. Estimate effort for
Product's prioritization (§ Product, above), for the review share of the work — the gate
itself takes time and belongs in the total, same as every other role's share.

**Verifies the actual test code faithfully implements QA's scenarios/strategy** — not just
that tests exist and pass. Extends the already-decided split between mechanical and semantic checks (the
traceability check verifies structurally that a scenario/functionality link exists; Reviewer judges semantically
whether it's the *right* one) to test code specifically: the same kind of judgment a
mechanical check can't make. Reviewer is the only role positioned after Fullstack Developer
in the standard path, so this check has nowhere else to live.

**Write/action scope (A4):** read-only over the PR diff, CI results, and every prior role's
artifacts; writes only its own PR review/findings comment — never edits code. This matches the
*effect* of the `pre-merge-review` skill's own `allowed-tools` contract excluding
`Edit`/`Write` (used here as the model for stating the same restriction in prose, not as a
stronger sandboxing guarantee — `pre-merge-review`'s own `allowed-tools` still includes `Bash`,
so the parity is in intent, not in enforcement).

**Security review triggers:** when a change touches one of the six categories below,
invoke the existing `security-review` skill. Risk-driven, not always-on — no separate Security
agent by default (one is justified only when a trigger applies *and* the stakes are high: real
user credentials, payment data, a publicly accessible production environment). POLP (Principle
of Least Privilege) is the organizing premise for every row: is this limited to the minimum
actually needed, and does a test prove that exceeding it is refused?

| Trigger category | Minimal test (POLP question) |
| --- | --- |
| Auth/session management | Access with less than the required role/scope is refused — not just "unauthorized refused" in general, but specifically *excess* privilege refused. |
| Secrets/credentials | The credential used itself has minimal scope (a scoped token, not a master key); no secret value leaks into logs/diff/output (e.g. a secret scan such as `gitleaks`). |
| Deploy/CI configuration | The granted permissions/scope are the minimum for the task — e.g. CI workflow permissions explicit and read-only, only expanded when a step genuinely needs it. |
| Infrastructure as Code | The provisioned resource/role has minimal privileges, no broad/wildcard grants; a plan/dry-run diff is reviewed before apply, never applied blindly. |
| Sensitive/personal data | Access to the data is limited to what is actually needed (minimal scope, minimal retention period) — per the privacy NFR. |
| Untrusted input (API/CLI/webhook) | The input handling operates with minimal privileges on that input — validates before use in a privileged operation, never passes untrusted input directly into a privileged operation (the "no `eval`" principle, applied more broadly). |

No new risk taxonomy — the same OWASP-top-10-like categories this project already implicitly
uses as a baseline (security as an explicit responsibility
of the Reviewer, not a separate taxonomy).

**Evidence / gates it produces:** pull-request review, technical findings (includes any bug
found at this gate, reported the same way as a code-quality finding — same channel the
`pre-merge-review` skill already uses, no separate bug-report artifact), approval or
rejection.

**On approval, posts the approval marker itself.** When the verdict is approval, include in
that same approval comment the approval marker exactly as the `pre-merge-review` skill defines
it, pinned to the PR's current HEAD commit SHA. The marker's format is defined once, there;
do not retype it from memory. Any comment, from anyone, carrying it pinned to the PR's current
HEAD satisfies the merge guard, so Reviewer's own approval is sufficient: no redundant second,
generic `pre-merge-review` dispatch is needed just to produce the marker a rigorous Reviewer
pass already earned. A **request-changes** verdict never posts the marker, same semantics as
`pre-merge-review`'s own: it means "reviewed and cleared," not merely "reviewed."

---

## Shared, across all five roles

**When your recommendation is not accepted (TiesL/spec-driven-guardrails#415).** Before the decision is recorded,
push back once with arguments for your recommendation and an explanation of
the cost of the maintainer's alternative. The orchestrator relays it, and the
maintainer may then hold the position and overrule. Do not repeat the pushback
after that. The numbered human decision links the pushback. A recommending
Reviewer is a fresh Reviewer for this dispatch. Non-Reviewer reuse remains
TiesL/spec-driven-guardrails#412's decision. An overrule then gets the Architect's issue Risk note in the
format above; this is the format referenced by TiesL/spec-driven-guardrails#410 AC6/S218.

Product decides *what*; Architect decides *how*; Fullstack Developer executes; QA verifies it
works as intended; Reviewer independently confirms the whole chain before release. Conflict
between roles is expected, not a model failure — it escalates, it doesn't get suppressed
(A7). It escalates to the project's human decision-maker.

**Every role's write/action scope also includes its own stage report.** Each of the five
Write/action scope clauses above names that role's *deliverable* artifact only; every role,
in addition, may always write the report recording its own stage's findings and evidence — an
issue/PR comment (or a `wip/<slug>/<ROLE>-REPORT.md` file during a co-thinking session, per A6)
— regardless of whether that role's own deliverable list above happens to mention comments
explicitly. Stated once, here, cross-role, rather than repeated in each of the five clauses
above (repeating it five times is exactly the duplication this file's single-document shape is
meant to avoid).

**Your report's first line is your `model-record` marker, never typed by hand.** It is
the output of the `model-record-emit.sh` command in your dispatch prompt, run with your own
exact model id as `--model` (the Reviewer also adds `--floor-basis`), pasted unchanged. No
effort is recorded (TiesL/spec-driven-guardrails#424). If your
prompt has no command (it is missing), run the wrapper yourself
(`skills/pre-merge-review/model-record-emit.sh` in the guardrails clone, flags as in the
`model-choice` skill) and say in your report that the prompt lacked it; don't stop work over it.

**Finding facts is your own job; only real decisions go to the project's human
decision-maker** (A10, from the `grilling` skill; see Product's entry above for the method
itself). A fact (discoverable from the codebase, docs, other artifacts) gets looked up, by you
or a dispatched sub-agent, never asked of the decision-maker. Only a genuine decision (a
preference, a trade-off, a judgment call only that person can make) goes to them, and several
open decisions get batched in one round rather than trickled out one at a time.

**Commit and push per logical step on the work item's shared branch, without asking** (A11).
One branch per work item, not per role: roles already work sequentially on the same branch, no worktree-per-role. Never merge into
`main`, release, force-push, or run a destructive git operation — that stays human-only (A2).
Merging a work-item PR into a release branch follows the `release-branch-workflow` skill; in
the five-role pipeline the orchestrating session does that, never a dispatched role.

**On a halt mid-task, save the attempted diff as a patch artifact before reverting** (A12,
added 2026-09-29) — never committed or pushed, alongside the work item's own tracking
artifact, so a human or resumed session can find and act on it. Covers the halted path A11
doesn't: an unresolved dispute, a blocked gate, or an ambiguity nothing in scope can settle.

**Reporting a defect or finding (QA, Reviewer): minimal content structure, decided
2026-09-25.** Neither role had one specified before this — closing that gap now rather than
implying more rigor than existed. Whether posted as a PR comment or an issue comment, use:

- **Summary** — one sentence stating the defect.
- **Failure scenario** — concrete input/state that produces the wrong output or behavior;
  the evidence, not just an assertion.
- **Location** — file:line for a code-level finding; the relevant scenario ID (e.g. `S<n>`)
  for a scenario/behavior-level defect without a specific line.
- **Category** — short label for the kind of defect (e.g. correctness, regression,
  test-coverage, code-quality).
- **Class** — `design`, `code`, `test` or `spec` (A28): where the fix starts. Category says what
  kind of defect it is; Class names the role whose step the fix begins at, per the route table
  below. `design`: the cause is a decision about structure (a format, a contract or Interface, a
  Seam, a parsing approach, where a responsibility lives, a data shape), so a correct code fix
  would leave that decision in place. `code`: the implementation departs from a sound design.
  `test`: a test does not falsify what it claims. `spec`: an acceptance criterion or the PRD is
  wrong, ambiguous or missing. The reporting role proposes the class; the orchestrator never downgrades a class, and the Architect may record that a finding is not a design defect and route it as code.
- **Falsifying check** — the observable condition that a correct fix must meet, stated so that
  a test or a reader could show the defect gone. It replaces any "Fix:" line.
- **Verdict** — `CONFIRMED` (reproduced) or `PLAUSIBLE` (suspected, not yet reproduced) —
  never asserted as certain without naming which of the two it is.
- **Severity** — `low`, `medium`, or `high` (added 2026-09-29). Independent of Verdict: a finding can be `CONFIRMED` and still `low`
  (real, but not release-blocking), or `PLAUSIBLE` and `high` (suspected, but severe enough to chase
  down before merge). Neither axis substitutes for the other.
- **Fix cost** — `trivial`, `small` or `large` (added 2026-10-13): what fixing the finding
  costs, proposed by the Reviewer and re-checked by the orchestrator. This is the one definition of
  `trivial`; [`ORCHESTRATOR.md`](ORCHESTRATOR.md) points here and does not restate it. A fix is
  `trivial` only if all of T1-T6 hold. If any fails, or the tag is absent or doubtful, it is not
  trivial. `small` and `large` are every other fix and are not told apart by any rule.
  Only a `code` or `test` low can be trivial: a `design` or `spec` low starts at the Architect or
  Product and changes spec content, which T5 excludes, so it is deferred. The trivial fix follows the
  A28 class route. For trivial-tagged lows QA runs once per round, all together, and names the red
  check on the reviewed sha: an existing test, gate or `./check` step, or the Reviewer's Falsifying
  check run as a command. QA adds no test, scenario or assertion. If QA can name no red check, the
  tag is void and the low is deferred. The Developer makes the trivial-fix commit F, which has
  exactly one parent (`git rev-list --parents -n 1 F` prints two fields). A merge commit, or a fix
  folded into a blocking-fix commit, cannot be measured and is not trivial.
  - T1 Files: F touches only files already in the PR diff at the reviewed sha (the head the finding
    was pinned to, not the new HEAD): `git diff --name-only F^ F`, each in the set printed by
    `git diff --name-only <base>...<reviewed-sha>`. At most 2 files, and at most 1 of them is code
    or test. By path: any *.md file anywhere (including under templates/) is docs; anything
    else is code or test, including a comment-only change in a shell script, templates/*.sh and
    `ci.yml`.
  - T2 Size: F alone is at most 10 changed lines (added plus deleted, summed from
    `git diff --numstat F^ F`) and at most 1 hunk in a code or test file
    (`git diff -U0 F^ F -- <file> | grep -c '^@@'`). A binary or renamed file
    (`-` in numstat) is not trivial.
  - T3 Docs and comments: any wording, formatting, typo, grammar, re-wrap or link fix.
  - T4 Code and test: a typo or literal fix, a quoting or whitespace fix, an off-by-one or
    wrong-variable fix, or a message-text fix that brings the code to what the spec, the existing
    test oracle or the surrounding code already states. In a test file T4 covers non-assertion lines
    only; assertions and expected values fall under T5. A code or test fix also needs Verdict
    `CONFIRMED`, not `PLAUSIBLE`.
  - T5 Never allowed: new behavior, a new or changed test case or scenario (no new `TEST-SCENARIOS.md`
    ID), any change to an existing assertion, expected value or oracle, any change to spec content
    (PRD, ARCHITECTURE, TEST-SCENARIOS), a new file, function, CLI flag, env var, seam or dependency,
    or a change to a guard or gate (merge guard, hooks, `./check`, CI workflow, settings).
  - T6 Evidence: the existing test suite and CI pass on the fix commit, with no test edited to make
    that so. T1 and T2 are measured on F after it exists. If CI is red, or T1 or T2 fails then,
    revert F, defer the finding, run a fresh review of the new HEAD, and make no second trivial fix:
    the attempt is spent.
  Only T1, T2 and T6 are measured, with the commands above; the orchestrator reads T3-T5 from the
  diff and records its judgment in the Pipeline log.
- **Disposition** — how a finding outside the current change's own scope gets handled (added
  2026-09-29): **issue** (turned into its own issue immediately,
  if actionable and small), **holding-pen** (appended to a backlog epic the project
  recognizes), or **dismissed** (explicitly, with reasoning recorded). Never silently dropped,
  and never fixed inline without a scope-expansion decision. A finding within the current
  change's own scope (i.e. it gets fixed in this same PR) doesn't need this field — Disposition only
  applies once a finding is judged out of scope for the work at hand.

A finding names the defect, its class and a falsifying check, and never gives a fix, a patch or
code. There is no exception for a typo-level or one-line finding: its falsifying check is a single
line anyway. The same rule holds for the findings of QA and the Developer. Each class is routed
to the role that owns the fix (roles in order; the orchestrator runs the route, see
[`ORCHESTRATOR.md`](ORCHESTRATOR.md)), from whichever stage found the defect:

| Class | Route |
| --- | --- |
| `design` | Architect, QA, Developer, fresh Reviewer |
| `code` | QA (a red test for the defect), Developer, fresh Reviewer |
| `test` | QA, Developer, fresh Reviewer |
| `spec` | Product, then the Architect if the design is affected, QA, Developer, fresh Reviewer |

No new tooling: this is the same shape already produced by this project's own
review-finding conventions, written down as a standing content requirement instead of only
living in an ad hoc tool schema.
