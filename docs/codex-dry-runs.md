# Runtime dry-run evidence for #455

Release acceptance remains **unobserved** for the outstanding cases below.
Automated filesystem fixtures and configured CI checks are structural evidence.
The [dated operator-host record](https://github.com/TiesL/spec-driven-guardrails/issues/455#issuecomment-6155405547)
and [updated QA assessment](https://github.com/TiesL/spec-driven-guardrails/pull/489#issuecomment-6194073106)
provide bounded observations, not independently reproduced by this Developer.
No full manual acceptance scenario is complete. S294/S297/S299 structural
checks remain a separate evidence class; this refresh does not re-certify them.

| Surface | Bounded observation | Outstanding acceptance observations |
| --- | --- | --- |
| Codex CLI | Partial, 0.162.1: original macOS host fresh session `01a13f38-8b7e-7092-b7fe-181b4984b34b` reportedly read AGENTS, context, role-contracts and ORCHESTRATOR at feature HEAD `f71d9fd`. Independent MacBook terminal transcripts record actual reads in unopted session `01a13fc1-66b1-7242-90e2-abc215059404` and opted-in session `01a13fc5-30d2-7893-b793-85c00f49175d`. Answers describe routes/continuation/stops; no roles were dispatched. | S295, S298–S302, S304 remain partial/unobserved: matching/nonmatching skill use before dependent work; precedence/budget negatives; available fresh scoped roles and unforked Review; unavailable dispatch stop; artifact-based resume; every finding route and two-round Architect step/reset, including low-only/interrupted controls; uninterrupted ordinary handoffs; genuine decision/override/main-merge stops |
| Codex desktop | Partial maintainer testimony: MacBook desktop 26.1007.71326, task `Run read-only #455 dry run`, session `01a13fe1-661a-7453-ba78-1d1067e9d801`, reported AGENTS/context/skill/ORCHESTRATOR reads and correct hypothetical route guidance, with no trust warning. Version, title and session id were supplied by the maintainer; raw tool transcript was not supplied. Original host computer-use app selection was denied separately. | S296, S298–S302, S304 unobserved: full configuration and actual action transcript; restarted fresh session after adoption/update; matching/nonmatching skills; trust enabled/withheld and suppressed/unavailable guidance; actual dispatch, artifact-based resume, routes, continuation and stops |
| Claude Code | Partial authenticated 2.1.300 feature-adopted scratch loading: session `266ec384-7614-4b36-8dd1-26f06426c7eb` read skill/ORCHESTRATOR and compared saved SessionStart output with `--add-dir /private/tmp/sdg-455`. Without that allowed directory, symlink reads were denied. Explicit CLI `--resume` returned the same id. Earlier 2.1.296 authentication failure is historical; the real-main-checkout session lacked role-contracts. | S303 remains partial: authenticated default/repeated adoption and legacy backups; fresh/stopped-workflow-stage resume with an open finding; representative SessionStart/Bash PreToolUse/PostToolUse/SessionEnd and guarded Git/native-hook/bypass/CI behavior; fresh Review and finding loop-back. Process resumption alone does not establish workflow recovery. |
| second machine | Partial, real MacBook-Air-van-Ties, macOS 26.6.2, feature HEAD `f71d9fd`: maintainer Terminal observations cover absent local installation, initial/repeated adoption/status, moving the workflow checkout, stale owned-link/provenance diagnostics and repair, clean status, preserved adoption/owner bytes by `cmp`, local source resolution, and subsequent fresh CLI loading. Both hosts are macOS. | S298 remains partial: previously adopted shared-project transfer/clone from A to B (B's project was new); actual workflow version/revision update with before/after status and stale copied-block/readoption behavior; committed-artifact inspection for machine-path absence. Owned local-checkout relocation is observed, not this transfer/update variant. |

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
