# Runtime dry-run evidence for #455

Release acceptance remains **unobserved** for the outstanding cases below. Per
maintainer decision #455-D4, the deferred live variants are owned by QA in
[#503](https://github.com/TiesL/spec-driven-guardrails/issues/503) and are
collected during actual work; they are not a #455 pre-release gate. Partial
observations receive bounded credit only and are never upgraded to passes.
Automated filesystem fixtures and configured CI checks are structural evidence.
The [dated operator-host record](https://github.com/TiesL/spec-driven-guardrails/issues/455#issuecomment-6155405547)
and [updated QA assessment](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6194073106)
provide bounded observations, not independently reproduced by this Developer.
No full manual acceptance scenario is complete. S294/S297/S299 structural
checks remain a separate evidence class; this refresh does not re-certify them.

| Surface | Bounded observation | Outstanding acceptance observations |
| --- | --- | --- |
| Codex CLI | Partial, 0.162.1: original macOS host fresh session `01a13f38-8b7e-7092-b7fe-181b4984b34b` reportedly read AGENTS, context, role-contracts and ORCHESTRATOR at feature HEAD `f71d9fd`. Independent MacBook terminal transcripts record actual reads in unopted session `01a13fc1-66b1-7242-90e2-abc215059404` and opted-in session `01a13fc5-30d2-7893-b793-85c00f49175d`. Answers describe routes/continuation/stops; no roles were dispatched in these three sessions. The later inspected session `01a140ee-fdad-7580-b585-0765f4dfe18f` (continuation section) does record actual fresh dispatch. | S295, S298–S302, S304 remain partial/unobserved. Observed since this row's evidence (see continuation section, bounded credit only): matching skill (role-contracts) used in dependent work (S295); fresh unforked QA plus Review children from artifacts (S301); fresh-session resume from artifacts with an open later finding (S302); one QA → fresh Review handoff under an explicit continuation instruction (partial S304). Still unobserved: nonmatching skill use; precedence/budget negatives; Product, Architect and Developer dispatch and the full chain from Product; unavailable dispatch stop; design/spec routes, two-round Architect step/reset outside the bounded desktop pipeline, low-only/interrupted controls, stale-label and malformed-evidence negatives; neutral-prompt continuation; genuine decision/override/main-merge stops |
| Codex desktop | Partial maintainer testimony: MacBook desktop 26.1007.71326, task `Run read-only #455 dry run`, session `01a13fe1-661a-7453-ba78-1d1067e9d801`, reported AGENTS/context/skill/ORCHESTRATOR reads and correct hypothetical route guidance, with no trust warning. Version, title and session id were supplied by the maintainer; raw tool transcript was not supplied. Original host computer-use app selection was denied separately. | S296, S298–S302, S304 unobserved: full configuration and actual action transcript; restarted fresh session after adoption/update; matching/nonmatching skills; trust enabled/withheld and suppressed/unavailable guidance; actual dispatch, artifact-based resume, routes, continuation and stops |
| Claude Code | Partial authenticated 2.1.300 feature-adopted scratch loading: session `266ec384-7614-4b36-8dd1-26f06426c7eb` read skill/ORCHESTRATOR and compared saved SessionStart output with `--add-dir /private/tmp/sdg-455`. Without that allowed directory, symlink reads were denied. Explicit CLI `--resume` returned the same id. Earlier 2.1.296 authentication failure is historical; the real-main-checkout session lacked role-contracts. | S303 remains partial. SessionStart delivery, artifact-based route selection and one fresh QA dispatch were observed on 2.1.301 (continuation section; Developer and fresh Reviewer legs pending). Unobserved: repeated adoption and legacy backups live; representative Bash PreToolUse/PostToolUse/SessionEnd and guarded Git/native-hook/bypass/CI behavior; fresh Review and finding loop-back. Process resumption alone does not establish workflow recovery. |
| second machine | Partial, a real second machine, the maintainer's MacBook Air, macOS 26.6.2, feature HEAD `f71d9fd`: maintainer Terminal observations cover absent local installation, initial/repeated adoption/status, moving the workflow checkout, stale owned-link/provenance diagnostics and repair, clean status, preserved adoption/owner bytes by `cmp`, local source resolution, and subsequent fresh CLI loading. Both hosts are macOS. | S298 remains partial: previously adopted shared-project transfer/clone from A to B (B's project was new); actual workflow version/revision update with before/after status and stale copied-block/readoption behavior; committed-artifact inspection for machine-path absence. Owned local-checkout relocation is observed, not this transfer/update variant. |

The linked operator record gives dated commands, outputs, configuration, source
state, local paths and session identifiers where available. Its MacBook CLI and
adoption observations are attributed to maintainer terminal transcripts. This
Developer has not independently inspected those raw attachments. The original
host's `/private/tmp/455-cli-live-output.txt` is a last answer, not a raw tool
transcript. Desktop observations are a maintainer-provided task answer, not
independent trace verification. Hypothetical route answers establish guidance
understanding only; they do not establish actual dispatch or enforcement.

S300's absent Codex runtime-interception message was observed. Representative
live Claude/native-hook/bypass behavior remains unobserved. Missing trust,
budget and behavioral observations remain missing evidence; copied directories
on one host and the existing development pipeline do not substitute for the
controlled per-surface runs.

An active desktop QA → Developer → fresh Reviewer route can add bounded S304
evidence only with actual product/version, thread/child-session ids, prompts,
sequential results and absence of routine approval pauses recorded. The current
parent uses the real repository main checkout while children read feature
artifacts from `/private/tmp/sdg-455`; explicit dispatch instructions do not
establish automatic discovery in a freshly feature-adopted desktop project.
The linked QA report records only its QA leg at publication. This documentation
refresh does not claim downstream completion or the full five-stage chain,
other routes, two-round/reset controls, resume or required stops.

On 2026-10-15, the automated S297/S298 correction campaign covered valid
staged/committed tracked provenance, an absent worktree record, receipt in a
fresh clone and retained owned links after checkout A disappears. Both public
adopt/status commands must reject the indexed record without project/index
writes. The ten command cases failed before the code correction and passed
after it; normal ignored provenance, clone-local installation and relocation
remain green controls. These are filesystem/CLI observations on one host,
not live runtime or independent-machine acceptance. The
[round-4 QA strategy](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6199276898)
retains the full outstanding runtime campaign listed above.

## Feature-adopted continuation observations (2026-10-15 and 2026-10-16)

These are bounded live observations from the Pipeline log and the
[QA assessment after Review round 5](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6209140880),
which inspected the raw traces. They do not complete any full manual acceptance
scenario and do not close `runtime-dry-runs-unobserved`.

- **Codex CLI 0.162.1, 2026-10-15, QA to fresh Review.** Parent session
  `01a140ee-fdad-7580-b585-0765f4dfe18f` in isolated clone
  `/private/tmp/sdg-455-cli-live` at HEAD `049d278`: a fresh `codex exec` with one
  turn read AGENTS, session context, role-contracts and durable issue/PR/Pipeline
  artifacts, selected QA, then dispatched with `fork_turns:"none"`: QA child
  `01a140ef-bebf-7a00-9836-2d79b6cfb5cd` ([report](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6200008416)),
  Review lenses `01a140f1-4abd-7792-8d58-1a022b802d12` and
  `01a140f1-6dd3-73c0-b368-16f28f9585e6`, and lead
  `01a140f2-8ad2-7a30-8f62-9bafd11f660d` ([round-5 report](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6200091485),
  transported verbatim by the parent after the lead's own publication failed).
  Raw traces: `/private/tmp/455-cli-live.jsonl` and the native rollouts under
  `~/.codex/sessions/2026/10/15/`. See the [Pipeline log](https://github.com/TiesL/spec-driven-guardrails/issues/455#issuecomment-6155086172)
  and [operator record](https://github.com/TiesL/spec-driven-guardrails/issues/455#issuecomment-6155405547).
- **Claude Code 2.1.301, 2026-10-16, orchestrator continuation.** Parent session
  `f821800a-abb9-4dcd-9d44-ca1bec9f02c8` in feature-adopted clone
  `/private/tmp/sdg-455-claude-live` at HEAD `049d278`: SessionStart fetch and
  ORCHESTRATOR rules were delivered; the parent read artifacts, ran
  `review-rounds.sh` and `role-label-staleness.sh`, selected the test-class route
  and dispatched QA (`general-purpose`, not fork, agent `aed68537d71ebd512`,
  [report](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6209140880)),
  then the documentation-step Developer dispatch (agent `ae5a263445134aa7d`, per the Pipeline log). The route's fresh
  Reviewer leg had not happened when this was written.

Limits, as stated by QA:

- Both parent prompts explicitly instructed continuing to the next ordinary stage
  without routine confirmation. This is the runtime following guidance plus an
  explicit operator instruction, partial S304 evidence only; it does not show
  continuation driven by guidance alone.
- The CLI parent stopped at the finding-route boundary after Review round 5
  without dispatching the test-class QA. Cause is not isolated (prompt said
  "the next ordinary stage", singular; Pipeline-log writes also failed). It is
  tracked as PLAUSIBLE medium/test `cli-continuation-stopped-at-route-boundary`.
- CLI rollouts carry originator "Codex Desktop" with source `exec`. This is
  CLI-surface evidence and gives Codex desktop no credit.
- Every variant QA lists as unobserved stays unobserved. The table's outstanding
  column is read together with the bounded credit named in this section and in
  its notes; nothing here upgrades a partial observation to a pass.
- Under #455-D4 the unobserved variants are deferred to #503 and are not a
  #455 pre-release full-matrix gate. An observed failure remains a defect to
  assess, and D4 does not waive `cli-continuation-stopped-at-route-boundary`.

Still outstanding (deferred to QA-owned [#503](https://github.com/TiesL/spec-driven-guardrails/issues/503) under #455-D4; operator-owned and not claimed here): Codex desktop in a
freshly feature-adopted project (restart, five-stage chain with raw per-dispatch
transcripts, controlled interruption and resume, unavailable-dispatch stop,
trust enabled/withheld, matching/nonmatching skills); a neutral-prompt Codex CLI
rerun that neither instructs continuation nor bounds it to one stage, a full
chain starting from Product, an unavailable-dispatch stop, design/spec routes,
low-only and interrupted controls, stale-label and malformed-latest-evidence
negatives, decision/override/merge-confirmation stops (never merging) and
precedence/budget negatives;
completion of the Claude route (Developer, fresh Reviewer) with live hook,
native-hook and CI behavior and repeated adoption with legacy backup; and
second-machine shared-project transfer, workflow revision update and
committed-artifact inspection.

For each run record:

- Date, exact runtime/product and version, OS, install mode and configuration;
  trust, permissions, instruction budget and parent/root/deeper instruction files.
- Workflow checkout revision and machine-local path, project branch/revision,
  public adoption/status output and fresh/restarted session evidence.
- Which policy rules, session-context output and invoked SKILL.md files were
  actually read before dependent work; nonmatching skills are not presumed used.
- Attempted action and observable result: distinguish absent capability, failed
  attempt and observed behavior. Include prompts and actual dispatch/session ids.
- Stage chain, each Review's artifact-only brief, finding links/slugs and class
  routes; two consecutive medium/high rounds and Architect reset; low-only and
  interrupted controls; resume from durable artifacts with an open later route.
- Unavailable dispatch stop and human stop/override decision, where applicable
  numbered bounded decision, pushback and Architect risk note; no fabricated
  emitter records or inferred consent. Main merge always awaits confirmation.
- Limitations, missing guidance, failed reads and unobserved variants. A routine
  “continue?” pause at a required ordinary handoff fails S304 continuation.

Codex web, third-party hosts and native Windows are outside the supported scope.
One-host two-path fixtures cannot establish a second-machine or additional OS
result. Version-specific discovery failures return to Architect without copied
skill bodies. Existing Claude baseline observations in README remain historical
baseline evidence, not a new #455 Claude dry run.

## Completion lifecycle observations (#500)

See [completion runtime evidence](completion-runtime-evidence.md) for the fresh
CLI 0.163.0 sentinel matrix, real local tag publication, interactive `/new` UI
observation and remaining desktop/Claude/reset gaps. Simulated PR state and
instruction following are explicitly distinguished from runtime enforcement.

## #544 hook protocol observation (2026-10-21)

A47 records real `PreToolUse` callbacks with `tool_name: Bash`,
`tool_input.command` and `cwd`. In the observed direct session, after exact-hook
review/trust, exit 2 with stderr `PROBE_544_REFUSAL` prevented the harmless denied
command from executing; silent exit 0 allowed the other marker command. The
synthetic first capture entry is excluded. Sanitized callbacks and the observed
outcomes are in `test/fixtures/codex-544-events.json`; replay tests establish
protocol wiring through the installed command and shared guard, not live loading.

The maintainer called this session CLI; saved metadata says CLI version 0.163.0,
originator Codex Desktop, source vscode. This discrepancy remains explicit;
separate desktop hook behavior remains unverified. Earlier nested probes without
callbacks remain inconclusive. Installing with `--hooks` reports structural
presence and `activation: unverified`; trust withheld, review pending, hooks
disabled, unsupported runtime or administrator suppression may prevent execution.
Adoption never grants trust or changes permissions. This observation does not
complete the unrelated #455 dry-run scenarios above.
