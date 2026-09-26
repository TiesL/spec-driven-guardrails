# Test scenarios — agentic-workflow-installer (v1: spec-driven-guardrails plugins)

Purpose: these scenarios describe the intended/observed behavior (see
`PRD.md`). They're independent of the chosen technical solution and
describe only observable behavior.

Notation: **Given / When / Then**.

Every scenario carries a `**Covers:**` field directly under its heading,
with the functionality from `PRD.md` that the scenario describes.
Comma-separated for more than one, e.g. `F3, F4`.

Scope note: these scenarios describe v1 — `spec-driven-guardrails` turned
into **two** Claude Code plugins, split by install scope (`spec-driven-
guardrails`, user scope, command + adoption skills; `spec-driven-
guardrails-workflow`, local scope, remaining skills + hooks — see
`ARCHITECTURE.md`'s "Build order decided"), not a generic multi-project
installer. "The manifest"/"declared" language in `PRD.md`'s F0-F9 refers
to the plugins' own embedded configuration for v1, not an external file.

---

## Plugin scope and hook confinement

### S-scope — A hook installed for one project never fires in another
**Covers:** N/A — cross-cutting architectural invariant (ARCHITECTURE.md A7), not a PRD.md F-item
- Given: `spec-driven-guardrails-workflow` (the local-scope, hook-carrying plugin) is installed in project A only; `spec-driven-guardrails` (the user-scope command plugin) is installed once, machine-wide
- When: the user opens an unrelated project B in the same Claude Code session and commits or pushes there
- Then: no hook from `spec-driven-guardrails-workflow` fires in project B — confinement is structural (local-scope install, `.claude/settings.local.json`), not a per-hook self-check
- And: the `/spec-driven-guardrails:adopt` command remains available in project B (it's user-scope), but invoking it there only ever affects project B if the user explicitly confirms adopting it, per F0-F4

### S-scope-b — A collaborator clones an already-adopted project
**Covers:** N/A — same as S-scope above (ARCHITECTURE.md A7)
- Given: project A was adopted (has `spec-driven-guardrails-workflow` installed at local scope, recorded in its own `.claude/settings.local.json`) and the collaborator has never installed either plugin themselves
- When: the collaborator clones project A and opens it in their own Claude Code session
- Then: the collaborator's session does not automatically fetch or run `spec-driven-guardrails-workflow` — local scope confines *installation*, it doesn't auto-propagate to a new machine
- And: this is a named, accepted residue (not a defect): a collaborator who wants the hooks active on their own machine installs the plugin the normal way

---

## Repository/identity bootstrap

### S0 — A workable repository context is established from scratch
**Covers:** F0
- Given: the target directory has no `.git`, no remote, no configured git identity, and `gh` is not authenticated
- When: F0 runs
- Then: it offers `git init`, `gh repo create`, asks for git identity confirmation, and triggers `gh auth login`'s browser flow, each explained in plain language and confirmed before acting — via `run_approved_command` (`ARCHITECTURE.md` A4)
- And: it never chooses a git identity's actual name/email value on the user's behalf

### S0b — A partial repository context is detected correctly
**Covers:** F0
- Given: the target directory already has a `.git` and a remote, but `gh` is not authenticated
- When: F0 runs
- Then: it reports the repository/remote as already satisfied and only prompts for the missing `gh auth login` step — it doesn't re-offer `git init`/`gh repo create` for what's already there

## Prerequisite detection and resolution

### S1 — All prerequisites already present
**Covers:** F1
- Given: the user's machine already has GitHub CLI and a supported Claude Code version installed (`git` is not checked — installing either plugin from a git-hosted marketplace already required it, per A6)
- When: the plugin runs prerequisite detection
- Then: it reports each prerequisite as present, in plain language, and proceeds directly to F3 without proposing any installation action

### S1b — A prerequisite is missing
**Covers:** F1
- Given: GitHub CLI (`gh`) is not installed on the user's machine
- When: the plugin runs prerequisite detection
- Then: it reports `gh` as missing, in plain language explaining what it's for, and does not proceed to F3/F4 until F2 resolves it
- And: no installation action is taken yet — detection only reports, it never acts

### S1c — Windows without WSL or Git Bash
**Covers:** F1
- Given: the plugin detects a Windows machine with neither WSL nor Git Bash present
- When: prerequisite detection runs
- Then: it reports WSL or Git Bash as a required prerequisite in plain language, explaining that the guardrails being installed (not just the installer) need one of them, and does not proceed to F3/F4 until resolved

### S2 — Guided resolution walks a missing prerequisite with confirmation
**Covers:** F2
- Given: F1 reported `gh` as missing on a macOS machine
- When: F2 explains why `gh` is needed and links the official install page for macOS
- Then: the plugin waits for the user to confirm they've installed it, re-checks, and only proceeds once confirmed — it does not run a package-manager install itself (decided 2026-09-26: detect and guide, not auto-install)

### S2b — User declines a proposed prerequisite install
**Covers:** F2
- Given: F2 has proposed installing a missing prerequisite
- When: the user declines the proposal
- Then: the plugin stops before F3, reports plainly that the prerequisite is required to continue, and does not silently retry or install anyway
- And: no partial installation side effect occurs from the declined step

### S2c — Resolution path unknown for the detected OS
**Covers:** F2
- Given: F1 detects a missing prerequisite on an OS the plugin has no standard install path for (`ARCHITECTURE.md` A5 requires macOS/Windows/Linux support; anything outside that)
- When: F2 attempts to propose a resolution
- Then: the plugin reports plainly that it doesn't have a known install path for this OS, names the prerequisite the user needs to install manually, and stops before F3
- And: it never guesses a command for an unsupported OS or silently falls back to a different OS's install path

## Conversational intake

### S3 — Answers collected one at a time with validation
**Covers:** F3
- Given: the plugin has confirmed all prerequisites are present
- When: it walks the embedded adoption questions (e.g. target directory, solo-or-shared project)
- Then: each question is asked individually in plain language, and an invalid answer (e.g. a directory path that doesn't exist) is rejected with a plain-language explanation before the next question is asked

### S3b — User cannot answer a question and needs to stop
**Covers:** F3
- Given: intake is mid-flow and the user is unsure how to answer a question
- When: the user asks to stop instead of answering
- Then: the plugin ends the conversation without executing any step, and no file or configuration is written to the target directory
- And: no progress-marker state is created for steps that never started

## Step execution

### S4 — Adoption steps run and narrate their outcome
**Covers:** F4
- Given: F3 has collected valid answers (target directory, project scope)
- When: F4 executes the embedded adoption steps (place skill files, install git hooks, symlink `CLAUDE.md`, seed the adoption table)
- Then: each step's purpose and outcome is narrated in plain language as it runs, and the target directory ends up in the same state `adopt.sh` would produce today

### S4b — A step fails partway through execution
**Covers:** F4
- Given: F4 is executing steps and a git hook install fails (e.g. the target directory's `.git/hooks` is not writable)
- When: the failure occurs
- Then: the plugin reports the specific failure in plain language, stops before running further steps, and does not report the overall install as successful
- And: steps that already completed are not re-run or duplicated on the next attempt (see F6)

## Preview

### S5 — Preview shows planned changes before anything runs
**Covers:** F5
- Given: F3 has collected valid answers
- When: the user asks to preview before committing
- Then: for every step F4 would run, its own plan/dry-run function reports what would change (which files, which hooks) without making any actual change to the target directory

### S5b — A step without an honest preview is refused, not run blind
**Covers:** F5
- Given: a primitive is added to F4's step set without a working plan/dry-run function
- When: preview is requested
- Then: the plugin reports that this step cannot be honestly previewed rather than silently skipping it or showing a fabricated no-op result
- And: F4 does not execute that step until its preview function exists

## Resume after interruption

### S6 — Resume continues from the next undone step
**Covers:** F6
- Given: a prior run completed steps 1-2 of F4 (each recorded `verified`, with evidence, and the plugin version it ran under — per `ARCHITECTURE.md` A3's two-field model) before the session was closed
- When: the plugin is invoked again against the same target directory
- Then: it reports steps 1-2 as already done, does not re-run them, and continues from step 3
- And: the same visible end state as an uninterrupted run — no duplicated files or hooks — is reached

### S6b — Interruption lands between a side effect and its verification
**Covers:** F6
- Given: a step's side effect (e.g. a file write) completed, but the interruption happened before that step's `verified` field was recorded
- When: the plugin resumes
- Then: it re-checks the target directory's actual state for that step — rather than trusting any stored flag — correctly identifies the step as already done, and does not duplicate the side effect
- And: if the actual state doesn't match what the step should have produced, it's reported as failed-and-incomplete, not silently marked done

### S6c — Plugin version drifted since the last recorded run
**Covers:** F6
- Given: a step's stored state records it ran under an older plugin version than the one now installed
- When: the plugin resumes
- Then: it reports the version mismatch in plain language and re-verifies that step's actual effect rather than trusting the stale record — since background plugin auto-update is off by default, this is an expected, not exotic, case

## Post-install verification

### S7 — Verification confirms success criteria per step
**Covers:** F7
- Given: F4 has completed all steps
- When: F7 runs
- Then: it checks each step's declared success criteria (files present with expected content, git hooks executable, adoption table seeded) and reports pass/fail per criterion in plain language, not just an overall "done"

### S7b — A step silently produced the wrong result
**Covers:** F7
- Given: F4 reported a step as complete, but its actual effect doesn't match the declared success criterion (e.g. a copied file's content doesn't match the expected template)
- When: F7 checks that criterion
- Then: it reports that specific criterion as failed, in plain language, rather than trusting F4's own completion report
- And: the overall install is reported as not fully successful — never "done" while any criterion fails

## De-adoption

### S8 — De-adoption removes the local-scope plugin natively
**Covers:** F8
- Given: a project has `spec-driven-guardrails-workflow` installed at local scope
- When: the user asks to de-adopt
- Then: the plugin runs `claude plugin uninstall --scope local` for that plugin in that project, confirmed before acting
- And: it reports the project-local residue (scaffolds already written, the `.gitignore` managed block) as a manual cleanup item, in plain language, rather than silently leaving it unmentioned

### S8b — De-adoption is requested but the plugin was never installed there
**Covers:** F8
- Given: the user asks to de-adopt a project that was never adopted (no local-scope plugin installed)
- When: de-adoption runs
- Then: it reports plainly that there's nothing to remove, rather than erroring or attempting an uninstall against nothing

## Re-adoption

### S9 — Re-running adoption after the workflow has changed
**Covers:** F9
- Given: a project was previously adopted, and the plugin's embedded step definitions have since changed (e.g. a new skill, an updated hook)
- When: the user re-runs adoption against the same project
- Then: plugin-owned files (`CLAUDE.md`, `.claude/settings.json`, git hooks) are backed up and overwritten; seed-once files (`PRD.md`, `TEST-SCENARIOS.md`, etc.) are left untouched since they already exist; managed-region files (the `.gitignore` block, `WORKFLOW-ADOPTION.md`) have only their managed region updated
- And: no user-edited content in a seed-once file is overwritten or lost

### S9b — Re-running adoption when nothing has changed
**Covers:** F9
- Given: a project is already fully adopted and the plugin's step definitions haven't changed since
- When: the user re-runs adoption
- Then: it reports the project as already up to date and makes no changes — a verified no-op, not a silent skip
