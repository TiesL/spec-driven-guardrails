# Test scenarios — agentic-workflow-installer (v1: spec-driven-guardrails plugin)

Purpose: these scenarios describe the intended/observed behavior (see
`PRD.md`). They're independent of the chosen technical solution and
describe only observable behavior.

Notation: **Given / When / Then**.

Every scenario carries a `**Covers:**` field directly under its heading,
with the functionality from `PRD.md` that the scenario describes.
Comma-separated for more than one, e.g. `F3, F4`.

Scope note: these scenarios describe v1 — `spec-driven-guardrails` turned
into one Claude Code plugin (`ARCHITECTURE.md`'s "Build order decided"),
not a generic multi-project installer. "The manifest"/"declared" language
in `PRD.md`'s F1-F7 refers to the plugin's own embedded configuration for
v1, not an external file.

---

## Prerequisite detection and resolution

### S1 — All prerequisites already present
**Covers:** F1
- Given: the user's machine already has git, GitHub CLI, and a supported Claude Code version installed
- When: the plugin runs prerequisite detection
- Then: it reports each prerequisite as present, in plain language, and proceeds directly to F3 without proposing any installation action

### S1b — A prerequisite is missing
**Covers:** F1
- Given: GitHub CLI (`gh`) is not installed on the user's machine
- When: the plugin runs prerequisite detection
- Then: it reports `gh` as missing, in plain language explaining what it's for, and does not proceed to F3/F4 until F2 resolves it
- And: no installation action is taken yet — detection only reports, it never acts

### S2 — Guided resolution installs a missing prerequisite with confirmation
**Covers:** F2
- Given: F1 reported git as missing on a macOS machine
- When: F2 explains why git is needed and proposes the standard macOS install path (e.g. Xcode Command Line Tools)
- Then: the plugin waits for the user's explicit confirmation before running any install action, and only proceeds once confirmed

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
- Given: a prior run completed steps 1-2 of F4 (each recorded `started` and `verified`, per `ARCHITECTURE.md` A3) before the session was closed
- When: the plugin is invoked again against the same target directory
- Then: it reports steps 1-2 as already done, does not re-run them, and continues from step 3
- And: the same visible end state as an uninterrupted run — no duplicated files or hooks — is reached

### S6b — Interruption lands between a side effect and its status update
**Covers:** F6
- Given: a step's side effect (e.g. a file write) completed, but the interruption happened before `verified` was recorded for that step
- When: the plugin resumes
- Then: it re-checks the target directory's actual state for that step rather than trusting a bare `started` flag, correctly identifies the step as already done, and does not duplicate the side effect
- And: if the actual state doesn't match what the step should have produced, it's reported as failed-and-incomplete, not silently marked done

## Post-install verification

### S7 — Verification confirms success criteria per step
**Covers:** F7
- Given: F4 has completed all steps
- When: F7 runs
- Then: it checks each step's declared success criteria (files present with expected content, git hooks executable, adoption table seeded) and reports pass/fail per criterion in plain language, not just an overall "done"

### S7b — A step silently produced the wrong result
**Covers:** F7
- Given: F4 reported a step as complete, but its actual effect doesn't match the declared success criterion (e.g. a symlink was created pointing at the wrong target)
- When: F7 checks that criterion
- Then: it reports that specific criterion as failed, in plain language, rather than trusting F4's own completion report
- And: the overall install is reported as not fully successful — never "done" while any criterion fails
