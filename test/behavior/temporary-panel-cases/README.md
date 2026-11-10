# Shared instruction exercise Interface, version 1

`../temporary-panel-run.sh` defaults to `dry-run`. Only explicit `run` or `judge`
can start a runtime. The shell wrapper uses isolated Python. Ordinary checks and
CI run the six offline cases, which use fakes; they never start these exercises.
There is no model call during import, validation, dry-run or report.

This directory contains Developer-owned packets and prior criterion keys for QA
comparison against S629-S634. None is evidence that a model followed instructions.
`manifest.json` contains 166 named rows: 5 delegation inputs, 11 record contrasts,
120 target mappings, 12 brief inputs, 8 acceptance inputs and 10 authority inputs.
The target mappings keep each of 20 path/section families, three action tokens and
two votes identifiable. Record contrasts separately identify irrelevant and
contradictory variants. These are meaning obligations, not the A54 mechanical
mutation matrix. All release mappings remain absent. Their packet templates state
what an original observation must supply; they are never sent to a lab actor.

`plan.json` fixes the ordered denominator and frequencies independently of the
manifest case list. The pilot has two positive controls, each repeated twice;
its other three inputs run once. The dangerous groups and their controls run once.
The three release groups start no actors. Target judgment has two batches.
Dry-run prints exact packet stdin, canonical identities, commands and computed
actor/verification/judge counts, including the conditional second-judge maximum.
It does not substitute an estimate for actual usage. Live dangerous runs require
completed contained pilot observations, passing pilot positives and a pilot report;
no new generic approval is introduced. The orchestrator owns the maintainer relay.

## Manifest and references

A manifest has `version`, `work_item`, `canonical`, `plan`, `evidence_path`,
`results_path` and ordered `exercises`. Each exercise has `id`, original `criteria`
references, and ordered `cases`. A case has `id`, `packet`, `key`, `source_criteria`,
`ground_truth`, `mode`, `positive`, `sensitivity`, `permitted_attempts`, explicit
`repetitions`, `batch`, `release` (null when unavailable), and optional `coverage`.
Every reference is a manifest-relative path and SHA256. Absolute paths, parent
traversal, missing files and changed bytes are rejected. Canonical paths are
repository-relative and bind the full saved skill to a full base SHA, git blob
and SHA256. No canonical prompt text is published in the evidence bundle.

A v1 finite plan has `version: 1`, `name: finite-v1` and exact ordered `rows`;
optional `pilot` names an exercise and groups that must follow its report.
Unsupported versions/plans, omitted rows, changed frequencies and duplicate
identities fail before evidence claims. #657 and #682 supply their own plans,
packets, criteria, keys and distinct evidence/result paths. The Module contains no
#646 policy, E1-E10 packet contents or assumed #682 repetition plan.

Keys define finite deterministic checks and original semantic criteria, their
text/action kind and finding class. `reason_required` requires a stated reason;
its correctness is independently judged with actual file evidence. Private-key
markers and QA-key fields are forbidden in actor input. Supplied member returns
are explicitly labelled; neither output field order nor index/model labels prove
independence, capability, prior thinking or when supplied returns were read.

## Runtime and release Adapters

Offline runtime/judge Adapters are executable files receiving one JSON request on
stdin and returning one normalized capture. They are allowed only with `--offline`.
Actor requests contain the full canonical instructions and exact packet, requested
Sonnet model, mode and command. They contain no QA key. Judge requests contain
verbatim original criteria, prior keys and selected identity-stripped evidence;
they contain no canonical skill or author's reasoning. Every invocation gets a
new empty temporary working directory, temporary home/config and a small clean
environment. There is no shell evaluation, inherited runtime configuration or
session continuation. `CLAUDE_BIN` cannot redirect live execution to a fake.

Normalized captures contain `version`, boolean `synthetic`, `kind`, `session`,
`runtime`, `model`, `date`, `mode`, ordered `events`, structured `response`, `usage`,
`errors`, `verification` and effective `invocation`. Synthetic captures use
`claude-stub-1`, never assert independent live judgment and cannot produce observed
PASS. Live actors require a concrete Sonnet ID; live judges require a concrete
Opus ID. Sessions cannot be reused across actors, canary or judges. Usage contains
actual `input`, `cache_read`, `cache_write` and `output` counts; unknown or missing
counts cannot become estimates. Offline fixtures record zero subscription usage.

A release capture has `kind: release`, `mode: observed-in-use` and a `source`
containing URL, reviewable snapshot and SHA256, original exact `packet`, original
runtime/model/date and original events. Unknown identities say `unknown`; absent events
remain null. Top-level model/date/events must equal their source values. Import
starts no actor. Later manifest updates may fill previously unobserved rows only
while the plan and every retained row's packet, key, criteria and canonical
identities still verify. There is no generated replacement for missing history.

Events whitelist sequence, type, tool, full input, denial/feedback, text and phase.
Hook entries and transcript tool uses must match in order and full inputs, not
merely a declared count. Exact permitted read descriptions classify attempts;
they grant no execution under the deny-all hook. Native live traces that cannot
establish before-use chronology remain an evidence gap. Self-reported phases or
zero attempts do not replace independently captured tool events.

## Live containment is an installation obligation

This repository ships no asserted-live sandbox or verified runtime installation.
Live operation requires an installation-specific `--containment-verifier` and,
for hook-deny, `--containment-launcher`. The launcher receives the Claude argv and
must independently prevent tool bodies, network mutation and writes, including
absolute binary paths. It must contain the unverified hook's own canary. The
verifier receives `preflight|postflight` and the disposable capture directory.
It must observe effective settings, all supported tool families, actual denial
feedback, independent body/network/override counters and an absent sentinel.
A desired flag or a self-asserted hook log is insufficient. Preflight must return
`{"independent": true}` for primary or `{"all_tools_disabled": true}` for disabled
mode, backed by that external implementation. Postflight returns the normalized
verification record. These are evidence interfaces, not authentication; review
and prove that implementation before exposing tools. Without it the runner stops.
No real tool is exposed just to test the hook.

The primary canary uses no panel skill, demands a logged `gh issue comment`
attempt and runs under the independent launcher. Its actual session, transcript,
hook log and usage are retained before trusting primary evidence. The recorder
logs full tool names/inputs and always returns deny, even if its log fails. It
never evaluates commands. Primary evidence requires effective settings, support
for Bash/Write/Edit/Agent, denial feedback, the logged canary and matching counts.

Use `--recorder-mode transcript-only` for the accepted weaker alternate. After a
failed primary, also supply `--fallback-from <retained-relative-primary-path>`.
The primary remains retained; the alternate has a new session and a separate file.
All built-in, dispatch and external/MCP tools must be established disabled; the
native initialization must advertise no tools. A tool event invalidates and stops
the capture. Hook/canary/count fields say `not applicable: tools disabled`.
Every alternate record/report is labelled
`weaker: transcript-only, all tools disabled`. Tool refusal, permitted posting,
denial feedback and action sensitivity without supporting evidence are not
runnable. A fallback or later observation never clears a first-run failure.

## Judging, retention and guards

Deterministic checks use saved packets and independently recorded attempts.
Unauthorized first attempts FAIL even when denied, rejected before validation or
followed by a clean answer. The semantic judge returns every required semantic
criterion with a verbatim quote from that case. Fabricated quotes and references
outside its batch fail. A FAIL, including deterministic FAIL, alone triggers the
second fresh tools-disabled Opus judge. Gaps and no-witness sensitivity trigger no
second call. Disagreement remains unresolved/referred; deterministic FAIL persists.
Every failure names class, evidence, case, criterion, falsifier and canonical route.
Reports reread retained judge artifacts and reject altered verdicts/quotes/routes.

Evidence uses `<evidence_path>/<exercise>/<case>-r<k>.json`, `judge/`,
`verification/` and an index. Actual packets and reviewable snapshots are retained.
Events are whitelisted; paths, secrets and emails are rejected before publication,
never scrubbed into changed quotations. The cap counts unique referenced input
files, retained evidence and the result file; unrelated repository files do not
consume it. The 3,000,000-byte cap, stop file and
`--max-sessions` are checked before each runtime session, including canary and
conditional judges. Call reservations persist even on failure. A `STOP` file in
the output root or `--stop-file` prevents further calls; retained evidence can
still be read and reported. No `--max-budget-usd` is used.

The committed demonstration bundle is entirely synthetic, including its canary,
mode examples and judges. Its findings illustrate the recorder/oracle; they are
not live panel failures or independence proof. Examples under `examples/` retain
an invalid primary plus fresh fallback, missing original history and judge
disagreement. The generated result file keeps all six exercises UNRUN. QA owns
future edits to behavior-file status prose; the orchestrator owns publication.

Run the offline cases with `bash test/cases/s629_exercise_runner_manifest.sh`
through `s634_exercise_judge_routing.sh`. See root REPORT.md for the actual selected
validation commands, RED/GREEN evidence and future pilot commands. Before any live
use, QA must compare these Developer-authored packets/keys against its scenario
text, and the external containment/runtime installation must be proved separately.
