# PRD — agentic-workflow-installer (design)

**Status:** Proposal/design for functionality still to be built. No code exists yet; this document specifies the system before it is built.

---

## Context

Two sibling projects — `spec-driven-guardrails` and `portfolio-mgt-agents` — are AI-assisted workflows meant to be used in conjunction with Claude (Code). Both need to reach third-party users who are **not software engineers**: people who will run the installation by delegating it to Claude Code, not by reading a README and typing shell commands themselves. A third such project is expected to follow. Reaching all of them without rebuilding the installer per project stays the long-term goal this project exists for.

`spec-driven-guardrails` already has an installer for a different audience: `adopt.sh` assumes the operator already has git, a configured shell profile, is comfortable exporting an environment variable (`SPEC_DRIVEN_GUARDRAILS_DIR`), and is intentionally adopting a *development* workflow into a project they're actively coding in. That's the right tool for that job, but it fails the non-engineer audience on several fronts: it requires manual shell setup, gives terse machine-oriented output, and assumes an existing git repository the user already understands.

**v1 scope, decided 2026-09-20 (see `ARCHITECTURE.md`'s "Build order decided"):** rather than building a generic, N-project installer core speculatively ahead of any real consumer, v1 turns `spec-driven-guardrails` itself into **one Claude Code plugin** that closes this gap for that one project first — asking questions and explaining actions in plain language, detecting and helping resolve prerequisites, running the adoption steps `adopt.sh` runs today but without requiring the user to hand-export an environment variable or already be comfortable in a shell. The plugin's internal structure keeps a generic side (no `spec-driven-guardrails` specifics) separate from a `spec-driven-guardrails`-specific side, so that generalizing to `portfolio-mgt-agents` and future projects — extracting the generic side into its own distributable "core" plugin — is a later, cheaper step once a second real consumer needs it, not a redesign. This document describes that v1 scope; the multi-project generic core remains the stated long-term goal, not this iteration's deliverable.

---

## Architecture

See `ARCHITECTURE.md` for the full decision record. Target shape: the system eventually splits into a **generic installer core** (prerequisite detection, the conversational question flow, plain-language narration, resumability, verification) and a **per-project manifest** that only declares *what* to install for that project — never *how* to phrase or run any of it. **For v1**, both live inside **one `spec-driven-guardrails` plugin**: the generic/specific split is enforced internally (own files — a `spec-driven-guardrails` literal in the generic side's files is the violation signal, per `ARCHITECTURE.md`'s "System boundaries and ownership") rather than as two separately distributed artifacts. Claude Code is the runtime that runs the plugin's scripts/skills, in conversation with the user.

---

## Data source(s)

N/A. The plugin reads local, per-run state — its own resume/progress marker in the target directory — there is no shared table, database, or external data source to document here. **For v1**, there is no external manifest file either: `spec-driven-guardrails`-specific configuration (which skills, which templates, which questions, which git hooks) is embedded directly in the plugin, mirroring `adopt.sh`'s own current split of `lib/` (generic-shaped) from the adopting script's own functions (project-specific). If a manifest format grows enough structure to warrant a schema reference — once a second project needs its specifics expressed externally — that belongs in a project-files entry, not this section.

---

## Functionality

### F1 — Prerequisite detection (`detect_prerequisites`)
Check which of `spec-driven-guardrails`' prerequisites (git, GitHub CLI, a specific Claude Code version) are present, which are missing, and which are present but below a required version. Reports findings in plain language before proposing any action. **For v1**, the prerequisite list is embedded in the plugin (not read from an external manifest); the "declared prerequisites" abstraction is deferred until a second project's plugin needs to express a different list.

### F2 — Guided prerequisite resolution (`resolve_prerequisite`)
For each missing or outdated prerequisite, explain in layman's terms why it's needed, propose the standard installation path for the user's detected OS, ask for confirmation, and only then act. Never installs anything silently.

### F3 — Conversational intake (`collect_answers`)
Walks `spec-driven-guardrails`' own adoption questions (e.g. "which directory should this live in", "is this a per-project adoption or the one-time, machine-wide setup" — `adopt.sh` today makes the latter choice via its `--user` flag; conversationally asked instead of requiring the user to know that flag exists) one at a time, in plain language, validating each answer before moving on. **For v1**, the question set is embedded in the plugin; a manifest-declared, per-project question set is deferred (see F1).

### F4 — Declarative step execution (`run_install_steps`)
Executes `spec-driven-guardrails`' adoption steps (place skill files, install git hooks, symlink `CLAUDE.md`, seed the adoption table — the same effects `adopt.sh`'s `install_skills`/`install_git_hooks`/`skill_symlink_update`/`seed_adoption_table` produce today) using the answers collected in F3, narrating each step's purpose and outcome as it happens. **For v1**, steps are the plugin's own tested primitives operating on embedded, `spec-driven-guardrails`-specific data — reimplemented cross-platform-safe (`ARCHITECTURE.md` A5), not a wrapper that shells out to `adopt.sh`'s existing Bash-only script body. A manifest-driven version of this (steps declared externally per project) is deferred to the generalization step.

### F5 — Dry run / preview (`preview_install`)
Reports what F4 *would* do — which files would be created or changed, which commands would run — without making any change, so the user can confirm before committing. **Each primitive (`ARCHITECTURE.md`'s "The decision") owns its own plan/dry-run function**; F5 is the aggregation of those per-primitive previews, not a generic mechanism layered on top — a primitive without an honest plan function cannot be previewed honestly, so every primitive in the core's set must define one (no primitive ships without it). **For v1**, this previews the plugin's embedded steps (F4); previewing an externally-declared manifest is deferred along with the manifest abstraction itself (see F1).

### F6 — Resume after interruption (`resume_install`)
Detects an install left incomplete by a prior run (closed terminal, lost connection, cancelled session) via a local progress marker, reports what's already done, and continues from the next undone step rather than restarting or duplicating side effects. **Per-step state is more than a `done` flag**: each step's record carries `started`, `verified`, a version/hash of the plugin's embedded step definitions it ran under, a hash of its inputs, and the verification evidence that proved it succeeded (see `ARCHITECTURE.md` A3). On resume, the core re-checks actual target state against `verified` — it never trusts a bare flag, since a crash can land between a side effect completing and its status being recorded.

### F7 — Post-install verification (`verify_install`)
After F4 completes, checks that the plugin's declared success criteria hold (files present, expected content, a smoke command exits zero) and reports pass/fail per criterion in plain language — not just "done". **For v1**, "declared" means embedded in the plugin, same as F1/F3/F4 — an externally-manifested criteria set is deferred along with the manifest abstraction.

---

## Non-functional characteristics

Fifteen subsections, one per characteristic from the register in `nfr/`.
**Answer each subsection with objective reasoning for *this* project — not
with the generic assumption from `Standaard`.** "N/A because …" is a valid
answer, provided it's substantiated: the point is that the question is
seriously asked and argued, not that every project must do equally much
everywhere.

<!-- nfr-block:begin — generated by ./generate-prd-block, don't edit by hand -->

### Security
<!-- nfr: spec-security -->
The installer core never asks a user to paste a credential in plaintext.
GitHub access goes through `gh auth login`'s own browser-based flow, which
the installer only triggers and waits on — it never sees or stores the
resulting token itself. The core needs no permissions beyond what the
target machine's own user account already has (writing files under a
directory the user chose, invoking `git`/`gh` under that user's existing
auth). Secrets never enter the plugin's step definitions (embedded for
v1, external manifest later): they declare *what* to ask for, never a
default value that could leak one.

### Data integrity
<!-- nfr: spec-data-integrity -->
The only persistent state the installer core owns is its own local
progress marker (F6) and whatever files F4's steps place in the target
directory (embedded plugin steps for v1, an externally-manifested set
later — see F1). The invariant that must hold: re-running a step whose
progress marker already says "done" is a no-op, not a re-execution — F4's
steps are written to be idempotent (checked via F5's preview matching F4's
actual effect). There is no concurrent-writer scenario to guard against:
installs are single-user, single-process, run from one interactive Claude
Code session at a time, so no locking or conflict-resolution mechanism is
needed for v1. Revisit if a future step writes to something outside the
target directory that another process could also touch.

### Failure modes
<!-- nfr: spec-failure-modes -->
Expected failures: a prerequisite fails to install (network drop, no
admin rights, unsupported OS) → F2 reports the failure in plain language
and stops before F4, never leaving a partial dependency install
unexplained. A step fails mid-run → F6's progress marker records
exactly which steps completed, so the next run resumes correctly instead
of re-running completed side effects or silently skipping the failed one.
An expired `gh auth` session mid-install → the affected step reports
"needs re-authentication" rather than a raw CLI error, and F6 lets the
user resume once re-authenticated. Every failure is narrated in the same
plain-language voice as success — a stack trace or raw exit code is never
the last thing a non-engineer sees.

### Observability
<!-- nfr: spec-observability -->
Because every step (F1-F7) runs synchronously inside a live, narrated
Claude Code conversation, "is it broken" is answered by the conversation
itself — there is no background job or unattended trigger in this design,
so a separate logging/alerting system is not warranted for v1 (unlike,
say, a scheduled job that could fail with nobody watching). F6's local
progress marker doubles as the durable record of what happened across
runs, readable by both the installer and a human inspecting the target
directory afterward.

### Performance and scale
<!-- nfr: spec-performance-scale -->
N/A for v1: the installer runs once per user per project, interactively,
bounded by how many steps the plugin's embedded step set declares
(expected: low tens). There is no volume of data or concurrent usage to
size for. Revisit only if the installer core is ever asked to drive a
bulk/unattended install across
many machines at once, which is explicitly not this design's target.

### Deployability
<!-- nfr: spec-deployability -->
There is no "environment" in the traditional sense (no server, no
pre-production/production split) — "deploying" this project means making
the `spec-driven-guardrails` plugin reachable by a non-engineer's Claude
Code session in the first place. `ARCHITECTURE.md` A6 narrows that
precondition to installing and signing into the Claude Desktop app
(verified: it bundles Claude Code); the literal step-by-step bootstrap
manual is still unwritten (`ARCHITECTURE.md`'s "Still open" section,
`PRD.md`'s Technical debt table), and is explicitly not written by this
PRD revision. **Correction (2026-09-20): declining a step is not
rollback.** Refusing to run a not-yet-executed step only prevents further
side effects — it does not undo effects a previous run already applied.
Undoing an already-applied step (true rollback/undo semantics) is out of
scope for v1 and would need explicit backup/undo logic per primitive if
ever added; F6/F5 give resumability and preview, not undo.

### Privacy
<!-- nfr: spec-privacy -->
N/A: the installer core processes no personal data beyond what already
exists locally on the user's own machine (their file paths, their
existing `gh` identity) and never transmits it anywhere the target
project's own tooling (`git`, `gh`) doesn't already send it. Nothing is
collected, retained, or seen by anyone other than the user running the
install.

### Compliance and auditability
<!-- nfr: spec-compliance -->
N/A: no regulated data category is processed (see Privacy above), and no
statutory retention obligation applies to a local, one-shot install run.
Revisit if a future step (embedded for v1, manifest-declared once one
exists) ever touches data covered by an external compliance regime.

### Backup and recovery
<!-- nfr: spec-backup-recovery -->
N/A as a distinct concern for this project: the installer never owns data
it didn't itself just create, and the target directory's own recovery
mechanism (typically git) is the target project's responsibility, not
this one's. The closest analogue — recovering from a bad or interrupted
install — is F6 (resume) and F5 (preview before committing), which are
specified as functionality, not as backup/recovery.

### Portability
<!-- nfr: spec-portability -->
Central to this project, not incidental: the non-engineer audience's
operating system is unknown in advance, so F1/F2 (prerequisite detection
and resolution) must work correctly on macOS, Windows, and Linux, using
each OS's own standard install paths rather than assuming a Unix shell
(unlike `install.sh`'s Bash-3.2-only, POSIX-shell assumption, which this
project cannot inherit unmodified). This is recorded as architecture
requirement A5.

### Maintainability
<!-- nfr: spec-maintainability -->
This is the reason for the core/manifest split (`ARCHITECTURE.md`'s
central decision, target shape). **For v1** (`ARCHITECTURE.md`'s "Build
order decided"), that split is enforced internally within one
`spec-driven-guardrails` plugin — generic-shaped logic in its own files,
`spec-driven-guardrails`-specific logic in its own — rather than as two
separately distributed artifacts yet. The yardstick for whether the split
is holding, once a second project exists: adding it requires only a new
plugin depending on the extracted generic side, not editing that generic
side for something project-specific. Unproven until that actually happens
(see Technical debt).

### Testability
<!-- nfr: spec-testability -->
F3/F4's step logic is designed to be tested against recorded/fake inputs
and a fake filesystem, independent of any real OS side effects — F5's
dry-run mode is exactly this seam exposed to the user as a feature. **For
v1**, "recorded/fake inputs" means the plugin's own embedded step
definitions (see F1); an external-manifest interpreter to test against is
deferred along with the manifest abstraction itself. Prerequisite
detection/resolution (F1/F2) is the part hardest to unit-test (it
inspects real OS state) and is expected to carry proportionally more
manual/integration-style verification once built, named here as a known
limitation rather than deferred silently.

### Usability
<!-- nfr: spec-usability -->
This is the project's central non-functional characteristic — the entire
reason it exists rather than reusing `adopt.sh`. Usable for someone with
no software engineering background, no assumed familiarity with git,
the terminal, or environment variables, operating the installer entirely
through a conversation with Claude Code rather than by reading
documentation or running commands themselves. Concretely: every
prerequisite check and step (F1-F7) explains *why* before acting (A2 in
`ARCHITECTURE.md`), asks rather than assumes when a choice is needed
(F3), and never surfaces a raw error, stack trace, or CLI exit code as
the final word (Failure modes above). The unwritten bootstrap manual
(Deployability above) is the largest remaining risk to this
characteristic actually holding in practice.

### Cost control
<!-- nfr: spec-cost-management -->
N/A: the installer core itself calls no paid API and consumes no billed
infrastructure — it drives local tools (`git`, `gh`) and the user's own
already-running Claude Code session, whose usage cost is between the user
and Anthropic, outside this project's control plane. Revisit if a future
version adds a hosted component — the plugin marketplace distribution
path (`ARCHITECTURE.md`'s "Still open") is Claude Code's own
infrastructure, not a billed component this project would run itself.

### Documentation
<!-- nfr: spec-documentation -->
`PRD.md` and `ARCHITECTURE.md` are kept current as design work proceeds,
per `write-spec` — updated as soon as the implementation (once it exists)
diverges from what's documented here, not left to drift. No formal API
specification exists yet; moot for v1 (no external manifest — see Data
source(s) above), relevant again once a second project needs the manifest
format fixed, at which point its schema becomes its own project-files
entry (see below) rather than being embedded in prose here.
<!-- nfr-block:end -->

---

## Out of scope

- Implementing the actual plugin (this revision is design-only, per the adopted `process-prd`/`architecture-document` agreements — see `WORKFLOW-ADOPTION.md`).
- The reusable, project-agnostic "core" as its own distributable component — v1 builds the generic/specific split internally, inside one `spec-driven-guardrails` plugin (`ARCHITECTURE.md`'s "Build order decided"); extraction is deferred to when a second project needs it.
- A concrete `portfolio-mgt-agents` plugin/manifest: that project has no application code yet (confirmed: `.claude/` is empty, its own README states "No application code exists yet"), so there is nothing yet to install. Its eventual plugin is future scope, not designed here.
- Splitting this PRD into GitHub issues (deliberately deferred — this round of work is documentation only).
- Writing the actual bootstrap manual (Claude Desktop app install/sign-in walkthrough) — now unblocked (`ARCHITECTURE.md` A6/"Still open") but not attempted in this round.

## Known limitations

What the system deliberately doesn't do or can't do. Stays this way unless
the scope changes — no action needed.

- Assumes one interactive install at a time, driven from a single live Claude Code session — no support for unattended/batch installs across many machines.
- Assumes the target is a project the user is setting up on their own machine — no remote-target or CI-driven install mode.

## Technical debt

What you'd build differently if you started over: incidental complexity,
deliberate shortcuts, outdated dependencies, missing tests. Accepted review
findings land here too. See *Complexity, technical debt, refactoring* in
`CLAUDE.md`.

| What | Why acceptable for now | Trigger to address it |
|---|---|---|
| No manifest format is fixed yet — F1/F3/F4 describe embedded, plugin-internal behavior, not an external schema | v1 is deliberately single-project (`ARCHITECTURE.md`'s "Build order decided"); fixing an external format before a second real consumer exists risks guessing wrong | Once a second project (e.g. `portfolio-mgt-agents`) needs its specifics expressed outside the `spec-driven-guardrails` plugin |
| The generic/specific split inside the plugin is a design intent, not yet a proven abstraction — only one real consumer exists | Can't be proven any other way than building a second consumer against it | Once a second project's plugin reuses the generic side unmodified (or fails to, revealing what the split got wrong) |
| The bootstrap manual (literal step-by-step for a non-engineer, from "nothing installed" to the plugin running) doesn't exist yet | Its trigger (deciding hybrid-vs-plugin) is now met, but writing and testing it against a real non-engineer is separate work not yet started | Before this plugin ships to a real non-engineer user; blocks that, not this document |

---

## Project files

| File | Purpose |
|---|---|
| `PRD.md` | This document — what the installer must do and why. |
| `ARCHITECTURE.md` | The core/manifest split decision, its requirements, and open questions. |
