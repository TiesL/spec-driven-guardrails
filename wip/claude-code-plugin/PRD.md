# PRD — `spec-driven-guardrails` Claude Code plugin (design)

**Status:** Proposal/design for functionality still to be built. No code exists yet; this document specifies the system before it is built.

**Document authority (decided 2026-09-26):** this file, `ARCHITECTURE.md`, and `TEST-SCENARIOS.md` in `wip/claude-code-plugin/` are the normative copies. The `agentic-workflow-installer` repo's copies are a historical snapshot from an earlier, generic-first exploration — superseded, not maintained further.

---

## Context

`spec-driven-guardrails` is an AI-assisted development workflow meant to be used in conjunction with Claude (Code), aimed at reaching third-party users who are **not software engineers**: people who will run the adoption by delegating it to Claude Code, not by reading a README and typing shell commands themselves. A sibling project, `portfolio-mgt-agents`, is a second intended consumer once it has application code to install; a co-thinking session on 2026-09-26 confirmed real, named candidate non-engineer users exist for the near term (independent portfolio-management and strategy-consulting profiles) — recorded privately, not in this document, since this repo is public.

`spec-driven-guardrails` already has an installer for a different audience: `adopt.sh` assumes the operator already has git, a configured shell profile, is comfortable exporting an environment variable (`SPEC_DRIVEN_GUARDRAILS_DIR`), and is intentionally adopting a *development* workflow into a project they're actively coding in. That's the right tool for that job, but it fails the non-engineer audience on several fronts: it requires manual shell setup, gives terse machine-oriented output, assumes an existing git repository the user already understands, and assumes an existing GitHub account/identity/authenticated `gh` session.

**v1 scope, decided 2026-09-20, revised 2026-09-26:** rather than building a generic, N-project installer core speculatively ahead of any real consumer, v1 turns `spec-driven-guardrails` into **two Claude Code plugins, split by install scope** — not one, as originally scoped (see "Architecture" below for why). Together they close the adoption gap for this one project first: asking questions and explaining actions in plain language, detecting and helping resolve prerequisites, establishing a workable repository context, running the adoption steps `adopt.sh` runs today but without requiring the user to hand-export an environment variable, already be comfortable in a shell, or already have a repository and identity configured. The plugins' internal structure keeps a generic side (no `spec-driven-guardrails` specifics) separate from a `spec-driven-guardrails`-specific side, so that generalizing to `portfolio-mgt-agents` and future projects is a later, cheaper step once a second real consumer needs it, not a redesign.

**Propagation model, decided 2026-09-26:** `adopt.sh`'s symlink model (workflow content always tracks the current `spec-driven-guardrails` checkout) is retired in favor of one copy-based mechanism, used everywhere including Ties' own machines — not two mechanisms running side by side. `adopt.sh` is marked author-only legacy, retired once the plugin passes the parity criterion (§F7) on all four of Ties' currently-adopted projects. See `ARCHITECTURE.md`'s propagation decision for why this is forced by the plugin mechanism itself, not only by Windows support.

**Funding decision, decided 2026-09-26, scope corrected 2026-09-26 (independent review):** only E1 (bootstrap admission manual) and E2 are funded now. **E2's scope is the two plugins plus a complete, direct (no primitive abstraction, no preview) implementation of F0-F4 and F7** — establishing repository context, detecting/guiding prerequisites, collecting answers, running the steps, and verifying the result — because the Usability success criterion below (a clean machine reaching a fully adopted, verified project) requires all of that to be funded, not deferred. What stays conditional: primitive extraction (E4), the aggregate preview UI (E5), full cross-platform hardening (E6/E7), and re-adoption (E3) — none of which the funded criterion depends on. See Epics below for the corrected table.

---

## Architecture

See `ARCHITECTURE.md` for the full decision record. Target shape: the system eventually splits into a **generic installer core** (prerequisite detection, the conversational question flow, plain-language narration, resumability, verification) and a **per-project manifest** that only declares *what* to install for that project — never *how* to phrase or run any of it.

**For v1**, both live inside **two `spec-driven-guardrails` plugins, split by Claude Code's own install scope** (decided 2026-09-26, resolving a hook-scoping hazard found after the original one-plugin design):

- **`spec-driven-guardrails`** (user scope): the `/spec-driven-guardrails:adopt` command and the adoption-time skills only. **No hooks.** Harmless to have installed in any project, including client/work repos, because it does nothing until explicitly invoked. Named plainly (not suffixed) since Claude Code namespaces a plugin's commands by the plugin's own name — this is the plugin the command must live in for `/spec-driven-guardrails:adopt` to actually be its invocation.
- **`spec-driven-guardrails-workflow`** (local scope, installed by the adopt command running `claude plugin install --scope local` *inside the confirmed target repo*): the other skills plus all hooks (`git-guardrails`, `push-after-commit`, session hooks). Local-scope install both fetches and structurally confines the plugin to that one directory via `.claude/settings.local.json` — a hook that isn't loaded in a project cannot fire there, by construction. No "adoption guard" self-check is needed; the earlier design considered one and it is not part of this document.

The generic/specific split is still enforced internally within each plugin (own files — a `spec-driven-guardrails` literal in the generic side's files is the violation signal, per `ARCHITECTURE.md`'s "System boundaries and ownership") rather than as separately distributed artifacts. Claude Code is the runtime that runs the plugins' scripts/skills, in conversation with the user.

---

## Data source(s)

N/A. The plugins read local, per-run state — their own resume/progress marker in the target directory — there is no shared table, database, or external data source to document here. **For v1**, there is no external manifest file either: `spec-driven-guardrails`-specific configuration (which skills, which templates, which questions, which git hooks) is embedded directly in the plugins, mirroring `adopt.sh`'s own current split of `lib/` (generic-shaped) from the adopting script's own functions (project-specific). If a manifest format grows enough structure to warrant a schema reference — once a second project needs its specifics expressed externally — that belongs in a project-files entry, not this section.

---

## Functionality

### F0 — Establish a workable repository context (`establish_repository_context`)
**Added 2026-09-26.** Before F1, confirm four things: a repository exists at the target path (or offer `git init`), a remote exists (or offer `gh repo create`), git identity is configured (`git config user.name`/`user.email` — the plugin asks, never silently assumes an identity for the user), and `gh` is authenticated (`gh auth login`'s browser flow, already specified under Security below). All four use `run_approved_command` (`ARCHITECTURE.md`'s A4 seam): confirmable, and reversible by simply not confirming. `adopt_project()`'s current hard-exit on a missing `.git` becomes F0's first branch rather than a dead end. Creating the GitHub *account* itself, and choosing the git identity's actual values, stay outside the plugin's reach — bootstrap-manual territory (A6), not this function.

### F1 — Prerequisite detection (`detect_prerequisites`)
Check which of `spec-driven-guardrails`' prerequisites (`gh`, Claude Code itself) are present, which are missing, and which are present but below a required version. **Version floor (decided 2026-09-26):** declared as whatever version E2 is actually built and tested against — not a lower, unverified guess — and checked mechanically by parsing `claude --version`. `git` is not checked here: installing either plugin from a git-hosted marketplace already requires `git`, so a machine that got this far already has it — `git` belongs in the bootstrap manual (A6), not F1. **Windows/Linux (decided 2026-09-26):** the guardrails this plugin installs (`git-guardrails`, the git hooks, the traceability checks) are Bash-and-`python3`, not portable by virtue of the installer being portable. F1 detects and declares WSL or Git Bash as a required prerequisite on Windows, rather than silently assuming a POSIX shell exists. Reports findings in plain language before proposing any action. **For v1**, the prerequisite list is embedded in the plugin; the "declared prerequisites" abstraction is deferred until a second project's plugin needs to express a different list.

### F2 — Guided prerequisite resolution (`resolve_prerequisite`)
For each missing or outdated prerequisite, explain in layman's terms why it's needed, propose the standard installation path for the user's detected OS (linking the official installer page), ask for confirmation, and only then act. **Detects and guides; does not drive package-manager installs itself** (decided 2026-09-26) — actually running Homebrew/winget/apt across three OSes is the riskiest, least testable code available and isn't v1's job. `gh auth login` is the one exception and stays automated to the browser flow, since it's a trusted, well-defined OAuth handoff, not an arbitrary package install.

### F3 — Conversational intake (`collect_answers`)
Walks `spec-driven-guardrails`' own adoption questions (e.g. "which directory should this live in", "is this a per-project adoption or the one-time, machine-wide setup" — `adopt.sh` today makes the latter choice via its `--user` flag; conversationally asked instead of requiring the user to know that flag exists) one at a time, in plain language, validating each answer before moving on. **The machine-wide (`--user`) path is in scope for v1** (decided 2026-09-26): with the plugins installed, the only remaining user-level artifact is the `~/.claude/CLAUDE.md` trigger file, which stays a real, explicit, confirmed user-level step the plugin performs — it cannot be folded into a plugin-carried skill (a plugin-root `CLAUDE.md` isn't loaded as project context, and a skill only loads on description-match, which defeats the trigger's own always-loaded purpose). **For v1**, the question set is embedded in the plugin; a manifest-declared, per-project question set is deferred (see F1).

### F4 — Declarative step execution (`run_install_steps`)
Executes `spec-driven-guardrails`' adoption steps (place skill files, install git hooks, symlink `CLAUDE.md`, seed the adoption table) using the answers collected in F3, narrating each step's purpose and outcome as it happens. **Implemented directly in v1, primitives extracted later (decided 2026-09-26):** rather than building the full execute/plan/verify primitive apparatus before a real step list exists, F4 is implemented directly against the embedded step list first; extracting it into the tested primitive set (`ARCHITECTURE.md`) is later work (see Epics), once real steps exist to generalize from — the same "de-risk before generalizing" principle `ARCHITECTURE.md`'s "Build order decided" already applies to the plugin split, applied one level deeper. Cross-platform-safe (`ARCHITECTURE.md` A5) regardless of when the extraction happens — not a wrapper that shells out to `adopt.sh`'s existing Bash-only script body.

### F5 — Dry run / preview (`preview_install`)
Reports what F4 *would* do — which files would be created or changed, which commands would run — without making any change, so the user can confirm before committing. Once primitives exist (F4's later extraction), each owns its own plan/dry-run function; a primitive without an honest plan function cannot be previewed honestly, so every primitive in the core's set must define one (no primitive ships without it). **For v1**, this previews the plugin's embedded steps (F4); previewing an externally-declared manifest is deferred along with the manifest abstraction itself (see F1).

### F6 — Resume after interruption (`resume_install`)
Detects an install left incomplete by a prior run (closed terminal, lost connection, cancelled session) via a local progress marker, reports what's already done, and continues from the next undone step rather than restarting or duplicating side effects. **Per-step state, decided 2026-09-26:** two fields, not five — `verified` (with evidence) and the plugin version the step ran under. `started` and an inputs hash are dropped: verification is authoritative (if `verify` passes, "did it start" adds nothing; if the user answers differently on re-run, verification simply fails and the step re-runs). The plugin-version field is kept specifically because plugin updates are manual, not automatic (Claude Code's background auto-update is off by default) — a user can easily be running a plugin version behind what their project's state recorded, and the version field is the thing a human can act on. On resume, the core re-checks actual target state against `verified` — it never trusts a bare flag, since a crash can land between a side effect completing and its status being recorded.

### F7 — Post-install verification (`verify_install`)
After F4 completes, checks that the plugin's declared success criteria hold (files present, expected content, an enumerated expected-tree parity check against what `adopt.sh` produces today, with intended deviations listed explicitly rather than left implicit) and reports pass/fail per criterion in plain language — not just "done". **For v1**, "declared" means embedded in the plugin, same as F1/F3/F4 — an externally-manifested criteria set is deferred along with the manifest abstraction.

### F8 — De-adoption (`uninstall`)
**Added 2026-09-26.** Removing `spec-driven-guardrails` from a project is `plugin uninstall --scope local` — a native Claude Code operation, not custom automation, since the local-scope plugin carries the hooks. Project-local residue (scaffolds already written, the `.gitignore` managed block) is documented as a manual cleanup note under Known limitations, not automated in v1.

### F9 — Re-adoption / upgrade (`reapply_adoption`)
**Added 2026-09-26, promoted to priority 3 among the epics (see Epics below).** Re-running adoption against an already-adopted project, after the workflow has changed, is the most frequent real operation over a project's lifetime and was previously unaddressed. Solved by classifying every file F4 places into one of three kinds, made an explicit field on each step definition rather than left implicit in which function places it: **plugin-owned, overwrite freely** (`CLAUDE.md`, `.claude/settings.json`, the git hooks — back up the previous copy, then replace); **seed once, never overwrite** (`PRD.md`, `TEST-SCENARIOS.md`, `ARCHITECTURE.md`, `CONTEXT.md`, CI files — the moment they're written, they're the user's content); **managed region inside a user-owned file** (the `.gitignore` block, `WORKFLOW-ADOPTION.md`'s append-only rows). Each class is idempotent by construction (overwrite / skip / marker respectively) — no merge engine or conflict UI needed. This became necessary once project-local content moved from symlinks (safe to re-adopt by construction) to copies (decided 2026-09-26, see Context) — a naive re-run under copies could otherwise silently overwrite a filled-in `PRD.md`.

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
Neither plugin ever asks a user to paste a credential in plaintext.
GitHub access goes through `gh auth login`'s own browser-based flow, which
the plugin only triggers and waits on (F0/F2) — it never sees or stores the
resulting token itself. Neither plugin needs permissions beyond what the
target machine's own user account already has (writing files under a
directory the user chose, invoking `git`/`gh` under that user's existing
auth). Secrets never enter the plugins' step definitions (embedded for
v1, external manifest later): they declare *what* to ask for, never a
default value that could leak one.

### Data integrity
<!-- nfr: spec-data-integrity -->
The only persistent state the plugins own is their own local
progress marker (F6) and whatever files F4's steps place in the target
directory (embedded plugin steps for v1, an externally-manifested set
later — see F1). The invariant that must hold: re-running a step whose
progress marker already says "done" is a no-op, not a re-execution — F4's
steps are written to be idempotent (checked via F5's preview matching F4's
actual effect, and by F9's per-class idempotence rule for re-adoption
specifically). There is no concurrent-writer scenario to guard against:
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
Because every step (F0-F9) runs synchronously inside a live, narrated
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
`spec-driven-guardrails` (the user-scope plugin) reachable by a
non-engineer's Claude Code session in the first place. `ARCHITECTURE.md` A6 narrows that
precondition to installing and signing into the Claude Desktop app
(verified: it bundles Claude Code); the literal step-by-step bootstrap
manual is E1 (see Epics), funded and next. **Correction (2026-09-20): declining a step is not
rollback.** Refusing to run a not-yet-executed step only prevents further
side effects — it does not undo effects a previous run already applied.
Undoing an already-applied step (true rollback/undo semantics) is out of
scope for v1; de-adoption (F8) is a native plugin uninstall, not
step-level rollback.

### Privacy
<!-- nfr: spec-privacy -->
N/A: the installer processes no personal data beyond what already
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
Central to this project, not incidental, and **narrower than originally
stated (decided 2026-09-26):** the non-engineer audience's operating
system is unknown in advance, so F0-F2 must work correctly on macOS,
Windows, and Linux, using each OS's own standard paths rather than
assuming a Unix shell. On Windows, WSL or Git Bash is a **declared
prerequisite** (F1), not silently assumed and not eliminated — the
guardrails this plugin installs (`git-guardrails`, the git hooks, the
traceability checks) are themselves Bash-and-`python3`, so the installer
being portable does not make the *installed workflow* portable. This is
recorded as architecture requirement A5.

### Maintainability
<!-- nfr: spec-maintainability -->
This is the reason for the core/manifest split (`ARCHITECTURE.md`'s
central decision, target shape). **For v1** (`ARCHITECTURE.md`'s "Build
order decided"), that split is enforced internally within each of the two
`spec-driven-guardrails` plugins — generic-shaped logic in its own files,
`spec-driven-guardrails`-specific logic in its own — rather than as two
separately distributed artifacts yet. The yardstick for whether the split
is holding, once a second project exists: adding it requires only a new
plugin depending on the extracted generic side, not editing that generic
side for something project-specific. Unproven until that actually happens
(see Technical debt).

### Testability
<!-- nfr: spec-testability -->
F4's step logic is designed to be tested against recorded/fake inputs
and a fake filesystem, independent of any real OS side effects, once
extracted into primitives (see F4) — F5's dry-run mode is exactly this
seam exposed to the user as a feature. **For v1**, "recorded/fake inputs"
means the plugin's own embedded step definitions (see F1); an
external-manifest interpreter to test against is deferred along with the
manifest abstraction itself. Prerequisite detection/resolution (F0-F2) is
the part hardest to unit-test (it inspects real OS/network/auth state)
and is expected to carry proportionally more manual/integration-style
verification once built, named here as a known limitation rather than
deferred silently.

### Usability
<!-- nfr: spec-usability -->
This is the project's central non-functional characteristic — the entire
reason it exists rather than reusing `adopt.sh`. Usable for someone with
no software engineering background, no assumed familiarity with git,
the terminal, or environment variables, operating the installer entirely
through a conversation with Claude Code rather than by reading
documentation or running commands themselves. Concretely: every
prerequisite check and step (F0-F9) explains *why* before acting (A2 in
`ARCHITECTURE.md`), asks rather than assumes when a choice is needed
(F3), and never surfaces a raw error, stack trace, or CLI exit code as
the final word (Failure modes above). **Success criterion, decided
2026-09-26:** one person matching the target profile, starting from a
machine with nothing installed, reaches a fully adopted project without
typing a terminal command and without more than one clarifying question
to a human, within 30 minutes — the joint acceptance criterion for E1+E2.
The unwritten bootstrap manual (Deployability above) is the largest
remaining risk to this characteristic actually holding in practice.

### Cost control
<!-- nfr: spec-cost-management -->
N/A: neither plugin calls a paid API or consumes billed
infrastructure — they drive local tools (`git`, `gh`) and the user's own
already-running Claude Code session, whose usage cost is between the user
and Anthropic, outside this project's control plane. Revisit if a future
version adds a hosted component — the plugin marketplace distribution
path is Claude Code's own infrastructure, not a billed component this
project would run itself.

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

## Epics (decided 2026-09-26)

Ordered by recommended sequence. Effort is a relative design/architecture-share estimate, not a final commitment.

| # | Epic | Priority | Funded | Effort |
|---|---|---|---|---|
| E1 | Bootstrap admission manual, tested against one real person | 1 | **Yes** | S |
| E2 | Two plugins (`spec-driven-guardrails` + `spec-driven-guardrails-workflow`), direct (non-primitive) implementation of **F0, F1, F2, F3, F4, F7** — a complete, verified, working adoption flow, no preview, no re-adoption, no cross-platform hardening beyond F1's WSL/Git-Bash detection | 2 | **Yes** | L |
| E3 | Step classification for re-adoption (F9) | 3 | Conditional | S |
| E4 | Four primitives (`check_tool`, `install_package` — pending Q8's detect-and-guide-only scope, `write_managed_block`, `run_approved_command`), each execute/plan/verify, extracted from E2's direct implementation | 4 | Conditional | M |
| E5 | Aggregate preview report (F5, user-facing) | 5 | Conditional | S |
| E6 | Windows/Linux execution hardening of the installer itself, beyond E2's basic detection | 6 | Conditional | M |
| E7 | Portability of the *installed payload* (Bash/python3 guardrails) — WSL/Git-Bash declared prerequisite, tested | 7 | Conditional | L |
| E9 | Generic core extraction — explicitly not v1 | Deferred | No | — |

**E8 does not exist.** An earlier draft had it as "`gh` detection/auth, Claude Code version floor" — folded into E2 once F0-F2 moved there (see "Why E2 includes F0/F1/F2/F7" below); the epic numbering was never compacted afterward, so E7 jumps straight to E9 deliberately, not by omission.

**Why E2 includes F0/F1/F2/F7 (corrected 2026-09-26, independent review finding):** the Usability success criterion below — a clean machine reaching a fully adopted, *verified* project without a terminal command — cannot hold if repository/identity bootstrap (F0), prerequisite handling (F1/F2), or verification (F7) are deferred to a conditional epic. They're funded as part of E2's direct implementation; only their later *extraction into tested primitives* (E4) and *aggregate preview UI* (E5) are conditional.

**Not gated on a real-user experiment (decided 2026-09-26):** both roles in the co-thinking session recommended watching one real target-profile person use the workflow for an hour before funding past E2. Ties declined this gate — E3 onward proceed on the sequencing above without that checkpoint.

---

## Out of scope

- Implementing the actual plugins (this revision is design-only, per the adopted `process-prd`/`architecture-document` agreements — see `WORKFLOW-ADOPTION.md`).
- The reusable, project-agnostic "core" as its own distributable component — v1 builds the generic/specific split internally, inside two `spec-driven-guardrails` plugins (`ARCHITECTURE.md`'s "Build order decided"); extraction is deferred to when a second project needs it.
- A concrete `portfolio-mgt-agents` plugin/manifest: that project has no application code yet (confirmed: `.claude/` is empty, its own README states "No application code exists yet"), so there is nothing yet to install. Its eventual plugin is future scope, not designed here.
- Splitting this PRD into GitHub issues (deliberately deferred — this round of work is documentation only).
- Automating de-adoption beyond `plugin uninstall --scope local` (F8) — project-local residue cleanup stays a documented manual step.
- The real-user experiment both roles recommended before funding E3 onward — explicitly declined (see Epics).

## Known limitations

What the system deliberately doesn't do or can't do. Stays this way unless
the scope changes — no action needed.

- Assumes one interactive install at a time, driven from a single live Claude Code session — no support for unattended/batch installs across many machines.
- Assumes the target is a project the user is setting up on their own machine — no remote-target or CI-driven install mode.
- De-adoption (F8) removes the local-scope plugin natively but does not automatically clean up project-local residue (scaffolds already written, the `.gitignore` managed block) — documented as a manual step.

## Technical debt

What you'd build differently if you started over: incidental complexity,
deliberate shortcuts, outdated dependencies, missing tests. Accepted review
findings land here too. See *Complexity, technical debt, refactoring* in
`CLAUDE.md`.

| What | Why acceptable for now | Trigger to address it |
|---|---|---|
| No manifest format is fixed yet — F0/F1/F3/F4 describe embedded, plugin-internal behavior, not an external schema | v1 is deliberately single-project (`ARCHITECTURE.md`'s "Build order decided"); fixing an external format before a second real consumer exists risks guessing wrong | Once a second project (e.g. `portfolio-mgt-agents`) needs its specifics expressed outside the `spec-driven-guardrails` plugins |
| The generic/specific split inside the plugins is a design intent, not yet a proven abstraction — only one real consumer exists | Can't be proven any other way than building a second consumer against it | Once a second project's plugin reuses the generic side unmodified (or fails to, revealing what the split got wrong) |
| The bootstrap manual (literal step-by-step for a non-engineer, from "nothing installed" to the plugin running) doesn't exist yet | It's E1, funded and next, but not yet written/tested | Before either plugin ships to a real non-engineer user; blocks that, not this document |
| E3's re-adoption, E4's primitive extraction, E5's preview UI, and E6/E7's cross-platform hardening are priced but not committed | Funding decision (2026-09-26): only E1+E2 are funded now | Ties decides to fund further, per the Epics table above |

---

## Project files

| File | Purpose |
|---|---|
| `PRD.md` | This document — what the plugins must do and why. |
| `ARCHITECTURE.md` | The core/manifest split decision, the two-plugin-by-scope architecture, its requirements, and open questions. |
| `TEST-SCENARIOS.md` | Given/When/Then scenarios per functionality item, `Covers:`-linked to `PRD.md`'s F-numbers. |
